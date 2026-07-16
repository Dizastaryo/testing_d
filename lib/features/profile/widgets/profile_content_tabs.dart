import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../../../core/models/file_item.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/author_tracks_provider.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/utils/format.dart';
import '../../library/collection_add_sheet.dart';
import '../../library/widgets/file_cover_widget.dart';
import '../../music/widgets/track_row.dart';
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
        // Раньше здесь был TweenAnimationBuilder с begin == end — счётчик не
        // анимировался вообще, только лишняя ребилд-обёртка.
        Text(formatCount(count), style: SeeUTypography.displayS),
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

// (ProfileFilesTab удалён — мёртвый: заменён ProfileAuthorTab, никем не
// импортировался. Хелперы _ProfileFileCard/_FileStat/userFilesProvider
// остались — их использует ProfileAuthorTab.)

/// Вкладка «Автор» (§05 A2): что пользователь сам выложил — треки в Аудиотеку
/// и файлы в Библиотеку, двумя секциями в одном скролле.
class ProfileAuthorTab extends ConsumerWidget {
  final String userId;
  const ProfileAuthorTab({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) return const SizedBox.shrink();
    final myId = ref.watch(authProvider).user?.id ?? '';
    final isMe = myId == userId;
    final tracks =
        ref.watch(authorTracksProvider(userId)).valueOrNull ??
            const <AudioTrack>[];
    final asyncFiles = ref.watch(userFilesProvider(userId));
    final files = asyncFiles.valueOrNull ?? const <FileItem>[];

    if (tracks.isEmpty && files.isEmpty) {
      if (asyncFiles.isLoading) {
        return const Center(
            child: CircularProgressIndicator(color: SeeUColors.accent));
      }
      return const SeeUEmptyState(
        icon: PhosphorIconsRegular.feather,
        title: 'Пока ничего не выложено',
        subtitle: 'Треки в Аудиотеку и файлы в Библиотеку появятся здесь',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      children: [
        if (tracks.isNotEmpty) ...[
          const _AuthorSectionHeader(
            icon: PhosphorIconsFill.musicNotes,
            gradient: [SeeUColors.plum, SeeUColors.info],
            title: 'Аудиотека · треки',
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < tracks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TrackRow(
                track: tracks[i],
                queue: tracks,
                index: i,
                source: 'profile',
                trailing: TrackRowTrailing.time,
              ),
            ),
          const SizedBox(height: 18),
        ],
        if (files.isNotEmpty) ...[
          const _AuthorSectionHeader(
            icon: PhosphorIconsFill.books,
            gradient: [Color(0xFFA0562E), Color(0xFF7A3F1E)],
            title: 'Библиотека · файлы',
          ),
          const SizedBox(height: 6),
          for (final f in files)
            _ProfileFileCard(
              file: f,
              isMe: isMe,
              onDelete: isMe
                  ? () async {
                      final confirmed = await showSeeUConfirm(
                        context,
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
            ),
        ],
      ],
    );
  }
}

/// Заголовок секции вкладки «Автор»: цветная иконка-плитка + подпись.
class _AuthorSectionHeader extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  const _AuthorSectionHeader({
    required this.icon,
    required this.gradient,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: SeeUTypography.subtitle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ],
      ),
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

// (_FileStat удалён вместе с ProfileFilesTab — его единственным потребителем.)

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
