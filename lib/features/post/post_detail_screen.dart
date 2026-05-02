import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../feed/widgets/post_card.dart';
import 'comments_screen.dart';

final _postDetailProvider =
    FutureProvider.family<Post, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final resp = await api.get(ApiEndpoints.postById(id));
  final data = resp.data;
  final postData = data is Map && data.containsKey('data') ? data['data'] : data;
  return Post.fromJson(postData as Map<String, dynamic>);
});

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  void _onShare(Post post) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surfaceElevated,
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
                  color: SeeUColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Поделиться', style: SeeUTypography.subtitle),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(PhosphorIcons.link(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title:
                    Text('Скопировать ссылку', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(
                      ClipboardData(text: 'https://seeu.app/p/${post.id}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ссылка скопирована',
                          style: SeeUTypography.body
                              .copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Отправить в сообщении',
                    style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Отправлено',
                          style: SeeUTypography.body
                              .copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.shareFat(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Поделиться в историях',
                    style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Добавлено в историю',
                          style: SeeUTypography.body
                              .copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.success,
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

  void _onMore(Post post) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surfaceElevated,
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
                  color: SeeUColors.borderSubtle,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Жалоба отправлена',
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
              ListTile(
                leading: Icon(PhosphorIcons.eyeSlash(PhosphorIconsStyle.fill),
                    color: SeeUColors.textSecondary),
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
  Widget build(BuildContext context, ) {
    final postAsync = ref.watch(_postDetailProvider(widget.postId));

    return Scaffold(
      backgroundColor: SeeUColors.background,
      appBar: AppBar(
        backgroundColor: SeeUColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Пост', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(),
              size: 22, color: SeeUColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          postAsync.whenOrNull(
                data: (post) => IconButton(
                  icon: Icon(PhosphorIcons.dotsThree(PhosphorIconsStyle.bold),
                      size: 22, color: SeeUColors.textPrimary),
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
                  size: 48, color: SeeUColors.textTertiary),
              const SizedBox(height: 16),
              Text('Не удалось загрузить пост',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.textSecondary)),
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
                        color: SeeUColors.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SeeURadii.pill),
                        border:
                            Border.all(color: SeeUColors.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.shareFat(),
                              size: 16, color: SeeUColors.textSecondary),
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
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CommentsScreen(postId: widget.postId),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: SeeUColors.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SeeURadii.pill),
                        border:
                            Border.all(color: SeeUColors.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.chatCircle(),
                              size: 16, color: SeeUColors.textSecondary),
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
            const Divider(height: 1, color: SeeUColors.borderSubtle),
            // Comments section title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Комментарии',
                      style: SeeUTypography.subtitle
                          .copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CommentsScreen(postId: widget.postId),
                        ),
                      );
                    },
                    child: Text(
                      'Все',
                      style: SeeUTypography.caption.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            CommentsSection(postId: widget.postId),
          ],
        ),
      ),
    );
  }
}
