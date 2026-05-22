import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/video_provider.dart';
import '../../../core/utils/format.dart';
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
        Text(label,
            style: SeeUTypography.micro.copyWith(fontSize: 11, color: c.ink3)),
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
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProfilePostsFeed(posts: posts, initialIndex: index),
          )),
          child: post.isWave
              ? Container(
                  color: post.waveColorValue != null
                      ? Color(post.waveColorValue!)
                      : SeeUColors.accent,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  child: Text(post.caption ?? '',
                      style: SeeUTypography.micro
                          .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                )
              : post.media.isNotEmpty
                  ? Stack(fit: StackFit.expand, children: [
                      CachedNetworkImage(
                        imageUrl: post.gridThumbnailUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) => Container(color: c.surface2),
                      ),
                      if (post.media.any((m) => m.type == MediaType.video))
                        Positioned(
                          top: 4, right: 4,
                          child: Icon(PhosphorIcons.play(PhosphorIconsStyle.fill),
                              color: Colors.white, size: 14,
                              shadows: const [Shadow(color: SeeUColors.mediumScrim, blurRadius: 4)]),
                        ),
                    ])
                  : Container(color: c.surface2),
        );
      },
    );
  }
}

class ProfileVideosTab extends ConsumerWidget {
  final String userId;
  const ProfileVideosTab({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) return const SizedBox.shrink();
    final asyncVideos = ref.watch(userVideosProvider(userId));
    return asyncVideos.when(
      loading: () => const Center(child: CircularProgressIndicator(color: SeeUColors.accent)),
      error: (_, __) => const SeeUEmptyState(
          icon: PhosphorIconsRegular.filmStrip, title: 'Не удалось загрузить'),
      data: (videos) {
        if (videos.isEmpty) {
          return const SeeUEmptyState(
              icon: PhosphorIconsRegular.filmStrip, title: 'Пока нет видео');
        }
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final v = videos[index];
            return GestureDetector(
              onTap: () => context.push('/videos/${v.id}'),
              child: Stack(fit: StackFit.expand, children: [
                v.thumbnailUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: v.thumbnailUrl, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: SeeUColors.surfaceElevated),
                        errorWidget: (_, __, ___) => Container(color: SeeUColors.surfaceElevated))
                    : Container(
                        color: SeeUColors.surfaceElevated,
                        child: const Icon(PhosphorIconsRegular.filmStrip, color: Colors.grey)),
                Positioned(
                  bottom: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(formatDuration(Duration(seconds: v.durationSeconds)),
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ]),
            );
          },
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
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final f = files[index];
            return ListTile(
              leading: Icon(_iconForMime(f.mimeType), color: SeeUColors.accent),
              title: Text(f.filename, style: SeeUTypography.body,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_formatSize(f.fileSize), style: SeeUTypography.caption),
              trailing: Icon(PhosphorIcons.arrowRight(), size: 18, color: SeeUColors.textSecondary),
              onTap: () => context.push('/files/${f.id}'),
            );
          },
        );
      },
    );
  }

  IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return PhosphorIconsRegular.image;
    if (mime.startsWith('video/')) return PhosphorIconsRegular.filmStrip;
    if (mime.startsWith('audio/')) return PhosphorIconsRegular.musicNote;
    if (mime.contains('pdf')) return PhosphorIconsRegular.filePdf;
    if (mime.contains('zip') || mime.contains('rar')) return PhosphorIconsRegular.fileZip;
    return PhosphorIconsRegular.file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
          Text('\u2013', style: TextStyle(fontFamily: 'Fraunces', fontSize: 56, color: c.ink3)),
          const SizedBox(height: 12),
          Text('Подпишитесь, чтобы видеть посты',
              style: SeeUTypography.body.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}
