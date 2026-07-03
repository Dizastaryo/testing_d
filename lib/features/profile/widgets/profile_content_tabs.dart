import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/file_item.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/utils/format.dart';
import '../../library/collection_add_sheet.dart';
import '../../library/widgets/file_cover_widget.dart';
import '../../post/profile_posts_feed.dart';

class ProfileStatItem extends StatelessWidget {
  final int count;
  final String label;
  const ProfileStatItem({super.key, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: count.toDouble(), end: count.toDouble()),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, value, child) =>
              Text(formatCount(value.toInt()), style: SeeUTypography.displayS),
        ),
        const SizedBox(height: 2),
        Text(label, style: SeeUTypography.kicker.copyWith(color: c.ink3)),
      ],
    );
  }
}

class ProfilePostsGrid extends StatelessWidget {
  final List<Post> posts;
  const ProfilePostsGrid({super.key, required this.posts});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    if (posts.isEmpty) {
      return const SeeUEmptyState(
          icon: PhosphorIconsRegular.imageSquare, title: 'Пока нет постов');
    }
    // M2: журнальная masonry-сетка — каждая плитка в опубликованном формате
    // (1:1 / 4:5 / 9:16) вместо жёсткого квадрата.
    return MasonryGridView.count(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
      crossAxisCount: 3,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final double ar = post.isWave
            ? 1.0
            : (post.media.isNotEmpty
                ? (post.media.first.aspectRatio ?? 0.8)
                    .clamp(0.5625, 1.0)
                    .toDouble()
                : 1.0);
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProfilePostsFeed(posts: posts, initialIndex: index),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SeeURadii.small),
            child: AspectRatio(
              aspectRatio: ar,
              child: post.isWave
                  ? Container(
                      color: post.waveColorValue != null
                          ? Color(post.waveColorValue!)
                          : SeeUColors.accent,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(6),
                      child: Text(post.caption ?? '',
                          style: SeeUTypography.micro.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    )
                  : post.media.isNotEmpty
                      ? Stack(fit: StackFit.expand, children: [
                          CachedNetworkImage(
                            imageUrl: post.gridThumbnailUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: c.surface2),
                            errorWidget: (_, __, ___) =>
                                Container(color: c.surface2),
                          ),
                          if (post.media
                              .any((m) => m.type == MediaType.video))
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                  PhosphorIcons.play(PhosphorIconsStyle.fill),
                                  color: Colors.white,
                                  size: 14,
                                  shadows: const [
                                    Shadow(
                                        color: SeeUColors.mediumScrim,
                                        blurRadius: 4)
                                  ]),
                            ),
                        ])
                      : Container(color: c.surface2),
            ),
          ),
        );
      },
    );
  }
}

class ProfileFilesTab extends ConsumerWidget {
  final String userId;
  const ProfileFilesTab({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) return const SizedBox.shrink();
    final myId = ref.watch(authProvider).user?.id ?? '';
    final isMe = myId == userId;
    final asyncFiles = ref.watch(userFilesProvider(userId));

    return asyncFiles.when(
      loading: () => const Center(child: CircularProgressIndicator(color: SeeUColors.accent)),
      error: (_, __) => const SeeUEmptyState(
          icon: PhosphorIconsRegular.folderSimple, title: 'Не удалось загрузить'),
      data: (files) {
        if (files.isEmpty) {
          return const SeeUEmptyState(
              icon: PhosphorIconsRegular.folderSimple, title: 'Пока нет файлов');
        }

        final totalDownloads = files.fold(0, (s, f) => s + f.downloadsCount);
        final totalLikes = files.fold(0, (s, f) => s + f.likesCount);

        return Column(
          children: [
            if (isMe)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                  border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.18)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _FileStat(label: 'Файлов', value: '${files.length}'),
                    _FileStat(
                        label: 'Скачиваний',
                        value: formatCount(totalDownloads)),
                    _FileStat(
                        label: 'Лайков', value: formatCount(totalLikes)),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                itemCount: files.length,
                itemBuilder: (ctx, index) {
                  final f = files[index];
                  return _ProfileFileCard(
                    file: f,
                    isMe: isMe,
                    onDelete: isMe
                        ? () async {
                            final confirmed = await showSeeUConfirm(
                              ctx,
                              title: 'Удалить файл?',
                              message: '«${f.displayTitle}» будет удалён.',
                              confirmLabel: 'Удалить',
                              destructive: true,
                              icon: PhosphorIcons.trash(),
                            );
                            if (confirmed) {
                              await ref
                                  .read(libraryActionsProvider)
                                  .deleteFile(f.id);
                              ref.invalidate(userFilesProvider(userId));
                            }
                          }
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

}

class _ProfileFileCard extends StatelessWidget {
  final FileItem file;
  final bool isMe;
  final VoidCallback? onDelete;

  const _ProfileFileCard({
    required this.file,
    required this.isMe,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.small),
              child: FileCoverWidget(
                  file: file,
                  width: 48,
                  height: 64,
                  borderRadius: SeeURadii.small),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.caption.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (file.authorName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      file.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.caption
                          .copyWith(fontSize: 11, color: c.ink3),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: SeeUColors.accent.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: Text(
                          file.formatLabel.toUpperCase(),
                          style: SeeUTypography.kicker.copyWith(
                            fontSize: 9,
                            color: SeeUColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(PhosphorIconsRegular.heart, size: 11, color: c.ink4),
                      const SizedBox(width: 3),
                      Text('${file.likesCount}',
                          style: SeeUTypography.mono
                              .copyWith(fontSize: 10, color: c.ink4)),
                      const SizedBox(width: 8),
                      Icon(PhosphorIconsRegular.download, size: 11, color: c.ink4),
                      const SizedBox(width: 3),
                      Text(file.downloadsFormatted,
                          style: SeeUTypography.mono
                              .copyWith(fontSize: 10, color: c.ink4)),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            if (!isMe)
              IconButton(
                icon: Icon(PhosphorIconsRegular.bookBookmark,
                    size: 18, color: SeeUColors.accent),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CollectionAddSheet(fileId: file.id),
                ),
              )
            else if (onDelete != null)
              IconButton(
                icon: const Icon(PhosphorIconsRegular.trash,
                    size: 18, color: SeeUColors.error),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _FileStat extends StatelessWidget {
  final String label;
  final String value;
  const _FileStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: SeeUTypography.mono.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SeeUColors.accent)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(),
            style: SeeUTypography.kicker.copyWith(color: c.ink3)),
      ],
    );
  }
}

class ProfilePrivateContent extends StatelessWidget {
  const ProfilePrivateContent({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('\u2013',
              style: SeeUTypography.displayXL
                  .copyWith(fontSize: 56, color: c.ink3)),
          const SizedBox(height: 12),
          Text('Подпишитесь, чтобы видеть посты',
              style: SeeUTypography.body.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}
