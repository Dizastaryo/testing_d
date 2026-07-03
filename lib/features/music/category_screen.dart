import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_discovery_provider.dart';
import '../../core/utils/format.dart';
import '../../widgets/full_screen_player.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  final String categoryId;

  const CategoryScreen({super.key, required this.categoryId});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  String _selectedSubcategory = '';
  String _selectedSort = 'trending';

  static const _sorts = [
    ('trending', 'Тренды'),
    ('newest', 'Новые'),
    ('popular', 'Популярные'),
    ('most_used', 'Для видео'),
  ];

  CategoryTracksParams get _params => CategoryTracksParams(
        category: widget.categoryId,
        subcategory: _selectedSubcategory,
        sort: _selectedSort,
      );

  void _playTrack(AudioTrack track, List<AudioTrack> queue) async {
    final idx = queue.indexWhere((t) => t.id == track.id);
    try {
      await ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: queue,
            index: idx >= 0 ? idx : 0,
            source: 'category:${widget.categoryId}',
          );
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
    }
  }

  void _showTrackMenu(AudioTrack track, List<AudioTrack> queue) {
    final c = context.seeuColors;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: track.coverUrl.isNotEmpty
                      ? CachedNetworkImage(imageUrl: track.coverUrl, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: c.surface2))
                      : Container(color: c.surface2,
                          child: Icon(PhosphorIcons.musicNote(), color: c.ink3, size: 16)),
                ),
              ),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.subtitle
                      .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
              subtitle: Text(track.displayArtist,
                  style: SeeUTypography.caption.copyWith(color: c.ink2)),
            ),
            Divider(height: 1, thickness: 0.5, color: c.line),
            ListTile(
              leading: Icon(PhosphorIcons.queue(), color: c.ink),
              title: Text('В плейлист',
                  style: SeeUTypography.body.copyWith(color: c.ink)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showAddToPlaylistSheet(context, ref, track.id);
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.info(), color: c.ink),
              title: Text('Подробнее',
                  style: SeeUTypography.body.copyWith(color: c.ink)),
              onTap: () {
                Navigator.pop(sheetCtx);
                context.push('/music/track/${track.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    final staticCat = findCategory(widget.categoryId);
    final async = ref.watch(audioCategoryTracksProvider(_params));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SeeURadarRefresh(
        onRefresh: () async => ref.invalidate(audioCategoryTracksProvider(_params)),
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _buildHeader(staticCat, c, theme),
            ),
            // Sort selector
            SliverToBoxAdapter(
              child: _buildSortBar(c),
            ),
            // Subcategory chips
            if (staticCat != null && staticCat.subcategories.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildSubcategoryChips(staticCat, c),
              ),
            // Tracks
            async.when(
              loading: () => const SliverToBoxAdapter(
                child: SizedBox(height: 400, child: SeeUListSkeleton(count: 8)),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: SeeUErrorState(
                    title: 'Не удалось загрузить категорию',
                    onRetry: () => ref.invalidate(audioCategoryTracksProvider(_params)),
                  ),
                ),
              ),
              data: (data) {
                if (data.tracks.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: SeeUEmptyState(
                        icon: PhosphorIconsRegular.musicNote,
                        title: 'Пока здесь нет треков',
                        subtitle: 'Загрузите первый трек в эту категорию',
                        action: SeeUStateAction(
                          label: 'Загрузить трек',
                          icon: PhosphorIconsRegular.uploadSimple,
                          onTap: () => context.push('/music/upload'),
                        ),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                  sliver: SliverList.builder(
                    itemCount: data.tracks.length,
                    itemBuilder: (_, i) =>
                        _trackTile(data.tracks[i], data.tracks, c),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      AudioCategoryModel? cat, SeeUThemeColors c, ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (cat?.color ?? SeeUColors.accent).withValues(alpha: 0.15),
            theme.scaffoldBackgroundColor,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SeeUBackButton(),
              const Spacer(),
              // Search access — navigates to the shared MusicSearchScreen.
              // Placed inside _buildHeader (a normal box widget) so it is
              // never directly in CustomScrollView.slivers.
              GestureDetector(
                onTap: () => context.push(
                    '/music/search?category=${Uri.encodeComponent(widget.categoryId)}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(PhosphorIconsRegular.magnifyingGlass,
                      size: 20, color: c.ink),
                ),
              ),
              if (cat != null) ...[
                const SizedBox(width: 4),
                SeeUChip(
                  label: cat.titleRu,
                  icon: cat.iconData,
                  bgColor: cat.color.withValues(alpha: 0.15),
                  fgColor: cat.color,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'КАТЕГОРИЯ',
            style: SeeUTypography.kicker.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 4),
          Text(
            cat?.titleRu ?? widget.categoryId,
            style: SeeUTypography.displayM
                .copyWith(color: theme.colorScheme.onSurface),
          ),
          if (cat?.description.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                cat!.description,
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSortBar(SeeUThemeColors c) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: _sorts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, label) = _sorts[i];
          final selected = _selectedSort == id;
          return GestureDetector(
            onTap: () => setState(() => _selectedSort = id),
            child: SeeUChip(
              label: label,
              bgColor: selected ? SeeUColors.accentSoft : c.surface2,
              fgColor: selected ? SeeUColors.accent : c.ink2,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubcategoryChips(AudioCategoryModel cat, SeeUThemeColors c) {
    final subs = [
      const AudioSubcategoryModel(id: '', titleRu: 'Все', titleEn: 'All'),
      ...cat.subcategories,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: subs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sub = subs[i];
          final selected = _selectedSubcategory == sub.id;
          return GestureDetector(
            onTap: () => setState(() => _selectedSubcategory = sub.id),
            child: SeeUChip(
              label: sub.titleRu,
              bgColor: selected
                  ? cat.color.withValues(alpha: 0.15)
                  : c.surface2,
              fgColor: selected ? cat.color : c.ink2,
            ),
          );
        },
      ),
    );
  }

  Widget _trackTile(AudioTrack track, List<AudioTrack> queue, SeeUThemeColors c) {
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;

    return InkWell(
      onTap: () {
        if (isCurrent) {
          ref.read(miniPlayerProvider.notifier).toggle();
        } else {
          _playTrack(track, queue);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.small),
              child: SizedBox(
                width: 52,
                height: 52,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIconsRegular.musicNote,
                            color: c.ink3, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.displayArtist,
                    style: SeeUTypography.caption.copyWith(color: c.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (track.isLikedByMe)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                    PhosphorIcons.heart(PhosphorIconsStyle.fill),
                    color: SeeUColors.like,
                    size: 14),
              ),
            Text(
              track.durationFormatted,
              style: SeeUTypography.mono.copyWith(fontSize: 11, color: c.ink3),
            ),
            const SizedBox(width: 8),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 28,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(PhosphorIconsRegular.dotsThreeVertical,
                  color: c.ink3, size: 18),
              onPressed: () => _showTrackMenu(track, queue),
            ),
          ],
        ),
      ),
    );
  }

}
