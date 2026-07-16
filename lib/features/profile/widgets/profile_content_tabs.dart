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
import '../../feed/widgets/post_card.dart';
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

/// §05 A/A3: «Публикации» = волны отдельным горизонтальным слайдером
/// (карточки 190px) + фото/видео двухколоночной сеткой ниже. Тап «Все N» →
/// режим «только волны» лентой с пилюлей возврата «← Все публикации».
class ProfilePostsGrid extends StatefulWidget {
  final List<Post> posts;
  const ProfilePostsGrid({super.key, required this.posts});

  @override
  State<ProfilePostsGrid> createState() => _ProfilePostsGridState();
}

class _ProfilePostsGridState extends State<ProfilePostsGrid> {
  bool _wavesOnly = false;

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts;
    if (posts.isEmpty) {
      return const SeeUEmptyState(
          icon: PhosphorIconsRegular.imageSquare, title: 'Пока нет постов');
    }
    final waves = posts.where((p) => p.isWave).toList();
    final media = posts.where((p) => !p.isWave).toList();

    if (_wavesOnly) return _buildWavesOnly(context, waves);

    final c = context.seeuColors;
    return CustomScrollView(
      slivers: [
        if (waves.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Row(
                children: [
                  Text('ВОЛНЫ',
                      style: SeeUTypography.kicker
                          .copyWith(fontSize: 10, color: c.ink3)),
                  const Spacer(),
                  Tappable(
                    onTap: () => setState(() => _wavesOnly = true),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Все ${waves.length}',
                            style: SeeUTypography.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SeeUColors.accent)),
                        Icon(PhosphorIconsBold.caretRight,
                            size: 11, color: SeeUColors.accent),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: waves.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _WaveSliderCard(
                  post: waves[i],
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ProfilePostsFeed(posts: waves, initialIndex: i),
                  )),
                ),
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childCount: media.length,
            itemBuilder: (context, index) =>
                _MediaGridTile(post: media[index], all: media, index: index),
          ),
        ),
      ],
    );
  }

  /// Режим «только волны» (§05 A3): пилюля возврата + лента полных волн.
  Widget _buildWavesOnly(BuildContext context, List<Post> waves) {
    final c = context.seeuColors;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Row(
            children: [
              Tappable(
                onTap: () => setState(() => _wavesOnly = false),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.arrowLeft,
                          size: 13, color: c.bg),
                      const SizedBox(width: 6),
                      Text('Все публикации',
                          style: SeeUTypography.caption.copyWith(
                              fontWeight: FontWeight.w600, color: c.bg)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('ВОЛНЫ · ${waves.length}',
                  style: SeeUTypography.kicker
                      .copyWith(fontSize: 10, color: c.ink3)),
            ],
          ),
        ),
        for (var i = 0; i < waves.length; i++) ...[
          PostCard(post: waves[i]),
          if (i != waves.length - 1)
            Divider(height: 24, thickness: 0.5, color: c.line),
        ],
      ],
    );
  }
}

/// Карточка волны в горизонтальном слайдере профиля (§05: 190px, r14).
class _WaveSliderCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const _WaveSliderCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final author = post.author;
    return Tappable(
      onTap: onTap,
      child: Container(
        width: 190,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ВОЛНА',
                style: SeeUTypography.kicker.copyWith(
                    fontSize: 8,
                    letterSpacing: 1,
                    color: SeeUColors.accent)),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                post.caption ?? '…',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Times New Roman',
                  fontFamilyFallback: const [
                    'Playfair Display',
                    'Georgia',
                    'serif',
                  ],
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  height: 1.45,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: (author.avatarUrl ?? '').isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: author.avatarUrl!, fit: BoxFit.cover)
                        : ColoredBox(color: c.surface2),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(author.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.micro.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: c.ink3)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Плитка фото/видео двухколоночной сетки (§05: r14).
class _MediaGridTile extends StatelessWidget {
  final Post post;
  final List<Post> all;
  final int index;
  const _MediaGridTile(
      {required this.post, required this.all, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final double ar = post.media.isNotEmpty
        ? (post.media.first.aspectRatio ?? 0.8).clamp(0.5625, 1.3).toDouble()
        : 1.0;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfilePostsFeed(posts: all, initialIndex: index),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: ar,
          child: post.media.isNotEmpty
              ? Stack(fit: StackFit.expand, children: [
                  CachedNetworkImage(
                    imageUrl: post.gridThumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: c.surface2),
                    errorWidget: (_, __, ___) => Container(color: c.surface2),
                  ),
                  if (post.media.any((m) => m.type == MediaType.video))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(PhosphorIcons.playCircle(PhosphorIconsStyle.fill),
                          color: Colors.white,
                          size: 20,
                          shadows: const [
                            Shadow(color: SeeUColors.mediumScrim, blurRadius: 4)
                          ]),
                    )
                  else if (post.media.length > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(PhosphorIcons.images(PhosphorIconsStyle.fill),
                          color: Colors.white,
                          size: 18,
                          shadows: const [
                            Shadow(color: SeeUColors.mediumScrim, blurRadius: 4)
                          ]),
                    ),
                ])
              : Container(color: c.surface2),
        ),
      ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    // §05 A2: бумажная библиотечная карта (#F3ECE0 / #E4D8C6, serif-название,
    // «N читателей · N сохранений»). В тёмной теме — нейтральные поверхности.
    final paperBg = dark ? c.surface : const Color(0xFFF3ECE0);
    final paperBorder = dark ? c.line : const Color(0xFFE4D8C6);
    final paperInk = dark ? c.ink : const Color(0xFF3A2A1E);
    final paperInk2 = dark ? c.ink3 : const Color(0xFF6A5A48);
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paperBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: paperBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Корешок-обложка 52×72 с книжной тенью.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7A3F1E).withValues(alpha: 0.2),
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: FileCoverWidget(
                  file: file, width: 52, height: 72, borderRadius: 6),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.displayS
                        .copyWith(fontSize: 16, color: paperInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMe
                        ? 'моя загрузка · ${file.formatLabel.toLowerCase()}'
                        : 'загрузка · ${file.formatLabel.toLowerCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.micro.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: paperInk2),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.users,
                          size: 12, color: paperInk2),
                      const SizedBox(width: 4),
                      Text(_readers(file.viewsCount),
                          style: SeeUTypography.micro.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: paperInk2)),
                      const SizedBox(width: 14),
                      Icon(PhosphorIconsRegular.bookmarkSimple,
                          size: 12, color: paperInk2),
                      const SizedBox(width: 4),
                      Text(_saves(file.likesCount),
                          style: SeeUTypography.micro.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: paperInk2)),
                    ],
                  ),
                ],
              ),
            ),
            // Действия
            if (!isMe)
              IconButton(
                icon: const Icon(PhosphorIconsRegular.bookBookmark,
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

  /// «84 читателя» с русским склонением.
  static String _readers(int n) {
    final m100 = n % 100, m10 = n % 10;
    if (m100 >= 11 && m100 <= 14) return '$n читателей';
    if (m10 == 1) return '$n читатель';
    if (m10 >= 2 && m10 <= 4) return '$n читателя';
    return '$n читателей';
  }

  /// «26 сохранений» с русским склонением.
  static String _saves(int n) {
    final m100 = n % 100, m10 = n % 10;
    if (m100 >= 11 && m100 <= 14) return '$n сохранений';
    if (m10 == 1) return '$n сохранение';
    if (m10 >= 2 && m10 <= 4) return '$n сохранения';
    return '$n сохранений';
  }
}

// (_FileStat удалён вместе с ProfileFilesTab — его единственным потребителем.)

/// §05 C: закрытый профиль — шапка видна целиком, контент заменён блоком
/// замка: карта r16 surface2, круг 44 с lock fill коралл.
class ProfilePrivateContent extends StatelessWidget {
  /// Имя владельца для человеческого текста («Лена ответит на запрос…»).
  final String? ownerName;
  const ProfilePrivateContent({super.key, this.ownerName});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final who = (ownerName != null && ownerName!.trim().isNotEmpty)
        ? ownerName!.trim().split(' ').first
        : 'Владелец';
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SeeUColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(PhosphorIconsFill.lockSimple,
                    size: 20, color: SeeUColors.accent),
              ),
              const SizedBox(height: 9),
              Text('Закрытый профиль',
                  style: SeeUTypography.caption.copyWith(
                      fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: 9),
              Text(
                'Актуальное и публикации скрыты. $who ответит на запрос — и контент откроется.',
                textAlign: TextAlign.center,
                style: SeeUTypography.micro
                    .copyWith(fontSize: 10.5, height: 1.5, color: c.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
