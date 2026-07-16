import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter/services.dart';
import '../../core/analytics/interest_tracker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import '../../core/design/design.dart';
import '../../core/models/explore_item.dart';
import '../../core/models/live_stream.dart';
import '../../core/providers/explore_feed_provider.dart';
import '../../core/providers/live_streams_provider.dart';
import '../../core/providers/waves_feed_provider.dart';
import '../feed/widgets/post_card.dart';
import '../live/live_viewer_screen.dart';

// ===========================================================================
// ExploreScreen widget
// ===========================================================================

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Best-effort: record the Explore visit and start a fresh impression window.
    final tracker = ref.read(interestTrackerProvider);
    tracker.resetImpressions();
    tracker.track(
        eventType: 'explore_open', entityType: 'explore', source: 'explore');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(exploreFeedProvider.notifier).loadMore();
    }
  }

  /// Opens an Explore item by type, recording the interest signal first
  /// (best-effort). Routing:
  ///   post  → /view (vertical publication viewer)
  ///   short → vertical full-screen Shorts viewer (9:16, fills the screen)
  ///   video → /videos/:id watch page (landscape, letterboxed meta layout)
  void _toast(String m) {
    if (!mounted) return;
    showSeeUSnackBar(context, m);
  }

  /// Long-press on an Explore cell → Instagram-style menu: «Не интересно»
  /// (feeds the ranking a negative signal + hides it), «Скрыть»,
  /// «Пожаловаться», «Копировать ссылку».
  void _onLongPressItem(ExploreItem it) {
    HapticFeedback.mediumImpact();
    final c = context.seeuColors;
    final id = it.entityId ?? '';
    final isPost = it.type == ExploreItemType.post;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(PhosphorIconsRegular.eyeSlash, color: c.ink),
              title: Text('Не интересно', style: SeeUTypography.body),
              subtitle: Text('Реже показывать подобное',
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
              onTap: () {
                Navigator.pop(sheetCtx);
                ref.read(interestTrackerProvider).track(
                      eventType: 'not_interested',
                      entityType: it.entityTypeName,
                      entityId: id,
                      authorId: it.author.id,
                      source: 'explore_menu',
                    );
                if (isPost && id.isNotEmpty) {
                  ref
                      .read(apiClientProvider)
                      .post(ApiEndpoints.viewPost(id))
                      .ignore();
                }
                ref.read(exploreFeedProvider.notifier).removeItem(it);
                _toast('Спасибо, будем реже показывать');
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.eyeClosed(), color: c.ink),
              title: Text('Скрыть', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (isPost && id.isNotEmpty) {
                  ref
                      .read(apiClientProvider)
                      .post(ApiEndpoints.viewPost(id))
                      .ignore();
                }
                ref.read(exploreFeedProvider.notifier).removeItem(it);
                _toast('Скрыто');
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.flag(), color: SeeUColors.like),
              title: Text('Пожаловаться',
                  style:
                      SeeUTypography.body.copyWith(color: SeeUColors.like)),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (id.isEmpty) return;
                showReportSheet(
                  context: context,
                  ref: ref,
                  targetType: isPost ? 'post' : 'video',
                  targetId: id,
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.link(), color: c.ink),
              title: Text('Копировать ссылку', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (id.isEmpty) return;
                final url = isPost
                    ? postShareUrl(id)
                    : 'https://seeu.app/videos/$id';
                Clipboard.setData(ClipboardData(text: url));
                _toast('Ссылка скопирована');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openItem(ExploreItem it) {
    final tracker = ref.read(interestTrackerProvider);
    final filter = ref.read(exploreFeedProvider).filter;
    switch (it.type) {
      case ExploreItemType.post:
        tracker.track(
          eventType: 'post_open_from_explore',
          entityType: 'post',
          entityId: it.postId,
          authorId: it.author.id,
          source: 'explore',
          metadata: {'filter': filter},
        );
        context.push('/view/${it.postId}?type=${it.isVideoPost ? 'video' : 'photo'}');
        break;
      case ExploreItemType.short:
        // Shorts (and the standalone video service that served them) were
        // removed. Such items are now filtered out of the Explore feed
        // upstream, so this case is unreachable — kept only for enum
        // exhaustiveness, same as ExploreItemType.video below.
        break;
      case ExploreItemType.video:
        // Long videos (the Видеотека section) were removed. Such items are now
        // filtered out of the Explore feed upstream, so this case is unreachable
        // — there's no watch page to open. Kept only for enum exhaustiveness.
        break;
    }
  }

  /// Records an impression for a grid item (de-duped per session by the tracker).
  void _trackItemImpression(ExploreItem it) {
    final filter = ref.read(exploreFeedProvider).filter;
    ref.read(interestTrackerProvider).impression(
          entityType: it.entityTypeName,
          entityId: it.entityId ?? '',
          authorId: it.author.id,
          metadata: {'item_type': it.entityTypeName, 'filter': filter},
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header: kicker + строка-вход в поиск + вкладки --
            _buildHeader(),

            // -- Content --
            Expanded(
              child: _contentForFilter(
                  ref.watch(exploreFeedProvider.select((s) => s.filter))),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Header: kicker + search entry + category tabs
  // =========================================================================

  // Вкладки-пилюли (§04): каждая — фильтр единой ленты /explore на бэке;
  // «Волны» и «Эфиры» — свои клиентские секции.
  static const List<String> _browseFilters = ['Все', 'Reels', 'Посты', 'Волны', 'Эфиры'];
  static const List<String> _browseFilterKeys = ['all', 'reels', 'posts', 'waves', 'live'];

  Widget _buildHeader() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ИНТЕРЕСНОЕ',
            style: SeeUTypography.kicker.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 12),

          // §04: поисковая СТРОКА — не поле. Тап открывает отдельный экран
          // поиска (мозаика дышит, экран открытий не перегружен).
          Tappable(
            onTap: () => context.push('/explore/search'),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF161310).withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.magnifyingGlass,
                      size: 18, color: c.ink3),
                  const SizedBox(width: 10),
                  Text('Искать людей, звуки, теги',
                      style: SeeUTypography.body
                          .copyWith(fontSize: 14, color: c.ink3)),
                ],
              ),
            ),
          ),

          // Вкладки-фильтры мозаики: Все · Reels · Посты · Волны · Эфиры.
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(
                _browseFilters.length,
                (i) {
                  final activeFilter = ref.watch(
                      exploreFeedProvider.select((s) => s.filter));
                  final key = _browseFilterKeys[i];
                  return _filterChip(
                    label: _browseFilters[i],
                    active: key == activeFilter,
                    showLiveDot: key == 'live',
                    onTap: () {
                      ref.read(interestTrackerProvider).track(
                        eventType: 'explore_filter_select',
                        entityType: 'filter',
                        source: 'explore',
                        metadata: {'filter': key},
                      );
                      ref.read(interestTrackerProvider).resetImpressions();
                      ref.read(exploreFeedProvider.notifier).setFilter(key);
                    },
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// Пилюля-вкладка (§04): активная — чёрная (#161310) с белым текстом,
  /// неактивная — белая с тонкой линией. Текст 600 12, обычный регистр.
  Widget _filterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool showLiveDot = false,
  }) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: SeeUMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.ink : c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: active ? null : Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // «Эфиры» несут живую красную точку — прямая трансляция сейчас.
              if (showLiveDot) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: SeeUColors.live,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? c.bg : c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Что показываем под чипами в режиме открытия (без активного поиска).
  Widget _contentForFilter(String filter) {
    switch (filter) {
      case 'live':
        return _buildLiveSection();
      case 'waves':
        return _buildWavesFeed();
      default:
        return _buildMixedGrid();
    }
  }

  // =========================================================================
  // Волны — лента текст-первых постов (§04 D)
  // =========================================================================

  Widget _buildWavesFeed() {
    final c = context.seeuColors;
    final async = ref.watch(wavesFeedProvider);
    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (e, _) => SeeUErrorState(
        title: 'Не удалось загрузить волны',
        onRetry: () => ref.invalidate(wavesFeedProvider),
      ),
      data: (waves) {
        if (waves.isEmpty) {
          return const SeeUEmptyState(
            icon: PhosphorIconsRegular.waveform,
            title: 'Пока нет волн',
            subtitle: 'Волна — текст-первый пост. Появятся здесь.',
          );
        }
        return RefreshIndicator(
          color: SeeUColors.accent,
          onRefresh: () async => ref.invalidate(wavesFeedProvider),
          child: ListView.separated(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: waves.length,
            separatorBuilder: (_, __) => Divider(
              height: 0.5,
              thickness: 0.5,
              color: c.line,
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (_, i) => PostCard(post: waves[i]),
          ),
        );
      },
    );
  }

  // =========================================================================
  // Live streams section
  // =========================================================================

  Widget _buildLiveSection() {
    final state = ref.watch(liveStreamsProvider);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    // Эфиры — живой полосой в две колонки (§04 E): каждая карточка иммерсивная
    // плитка с бейджем «Трансляция», числом зрителей и автором снизу.
    if (state.streams.isEmpty) {
      return SeeURadarRefresh(
        onRefresh: () => ref.read(liveStreamsProvider.notifier).refresh(),
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Text(
                  'Ошибка загрузки',
                  style:
                      SeeUTypography.caption.copyWith(color: SeeUColors.error),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: SeeUEmptyState(
                icon: PhosphorIconsRegular.broadcast,
                title: 'Нет активных эфиров',
                subtitle: 'Начните свой или подождите',
              ),
            ),
          ],
        ),
      );
    }

    return SeeURadarRefresh(
      onRefresh: () => ref.read(liveStreamsProvider.notifier).refresh(),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 150,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: state.streams.length,
        itemBuilder: (_, i) {
          final s = state.streams[i];
          return _LiveGridCard(
            stream: s,
            paletteIndex: i,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LiveViewerScreen(streamId: s.id),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // Mixed grid: tags + masonry posts grid
  // =========================================================================

  // Tags section removed - all content comes from backend search

  // =========================================================================
  // Mixed grid (all posts)
  // =========================================================================

  Widget _buildMixedGrid() {
    final c = context.seeuColors;
    final state = ref.watch(exploreFeedProvider);

    if (state.isLoading && state.items.isEmpty) return _buildGridShimmer();
    if (state.error != null && state.items.isEmpty) {
      return SeeUErrorState(
        title: 'Не удалось загрузить',
        onRetry: () => ref.read(exploreFeedProvider.notifier).refresh(),
      );
    }

    if (state.items.isEmpty) {
      return SeeURadarRefresh(
        onRefresh: () => ref.read(exploreFeedProvider.notifier).refresh(),
        child: ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                'Здесь пока пусто',
                style: SeeUTypography.body.copyWith(color: c.ink2),
              ),
            ),
          ],
        ),
      );
    }

    // §04: мозаика в ДВЕ колонки, плитки r14, высоты чередуются 150/122 —
    // шахматный ритм из дизайна. SliverMasonryGrid ленивый: ячейки строятся
    // по мере скролла, импрешны остаются в VisibilityDetector ячейки.
    return SeeURadarRefresh(
      onRefresh: () => ref.read(exploreFeedProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childCount: state.items.length,
              itemBuilder: (context, index) => _MasonryCell(
                key: ValueKey('explore_cell_$index'),
                item: state.items[index],
                index: index,
                height: index.isEven ? 150 : 122,
                onTapItem: _openItem,
                onImpression: _trackItemImpression,
                onLongPressItem: _onLongPressItem,
              ),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(child: _LoadingMoreIndicator()),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  // =========================================================================
  // Grid shimmer (loading state)
  // =========================================================================

  Widget _buildGridShimmer() {
    final c = context.seeuColors;
    // Скелетон повторяет мозаику §04: 2 колонки, r14, высоты 150/122.
    return SeeUShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          itemCount: 8,
          itemBuilder: (_, i) => Container(
            height: i.isEven ? 150 : 122,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

}

// ===========================================================================
// Masonry cell — плитка двухколоночной мозаики (§04): r14, высота 150/122,
// play-значок + длительность для видео. Ленивая: строится по мере скролла,
// импрешн — из VisibilityDetector ровно один раз.
// ===========================================================================

class _MasonryCell extends StatefulWidget {
  final ExploreItem item;
  final int index;
  final double height;
  final void Function(ExploreItem item) onTapItem;
  final void Function(ExploreItem item)? onImpression;
  final void Function(ExploreItem item)? onLongPressItem;

  const _MasonryCell({
    super.key,
    required this.item,
    required this.index,
    required this.height,
    required this.onTapItem,
    this.onImpression,
    this.onLongPressItem,
  });

  @override
  State<_MasonryCell> createState() => _MasonryCellState();
}

class _MasonryCellState extends State<_MasonryCell> {
  bool _impressed = false;

  void _onVisibility(VisibilityInfo info) {
    if (_impressed) return;
    if (info.visibleFraction > 0.5) {
      _impressed = true;
      widget.onImpression?.call(widget.item);
    }
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final item = widget.item;
    final isShort = item.type == ExploreItemType.short;
    final isVideo = item.type == ExploreItemType.video;
    final showPlay = isShort || isVideo || item.isVideoPost;
    final imageUrl = item.displayImage;
    // Декодируем в разрешении ячейки (~пол-экрана), не full-res.
    final cacheWidth = (MediaQuery.of(context).size.width /
            2 *
            MediaQuery.devicePixelRatioOf(context))
        .round();

    return GestureDetector(
      onTap: () => widget.onTapItem(item),
      onLongPress: widget.onLongPressItem == null
          ? null
          : () => widget.onLongPressItem!(item),
      child: VisibilityDetector(
        key: ValueKey('explore_vis_${widget.index}'),
        onVisibilityChanged: _onVisibility,
        child: SizedBox(
          height: widget.height,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: cacheWidth,
                    maxWidthDiskCache: cacheWidth,
                    placeholder: (_, __) => Container(color: c.surface2),
                    errorWidget: (_, __, ___) => Container(
                      color: c.surface2,
                      child: Icon(PhosphorIcons.image(), color: c.ink3),
                    ),
                  )
                else
                  Container(
                    color: c.surface2,
                    child: Icon(
                      showPlay
                          ? PhosphorIcons.playCircle()
                          : PhosphorIcons.image(),
                      color: c.ink3,
                    ),
                  ),
                // Видео: play-circle fill сверху-справа (§04).
                if (showPlay)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      PhosphorIcons.playCircle(PhosphorIconsStyle.fill),
                      color: Colors.white,
                      size: 20,
                      shadows: const [
                        Shadow(color: SeeUColors.mediumScrim, blurRadius: 4),
                      ],
                    ),
                  ),
                // Видео: длительность пилюлей внизу-слева (§04).
                if (showPlay && item.durationSeconds > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: SeeUColors.mediumScrim,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        _fmtDuration(item.durationSeconds),
                        style: SeeUTypography.micro.copyWith(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Audio track card
// ===========================================================================

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: SeeUColors.accent,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Live stream card for the Прямой эфир explore tab
// ============================================================================

class _LiveGridCard extends StatelessWidget {
  final LiveStream stream;
  final int paletteIndex;
  final VoidCallback onTap;

  const _LiveGridCard({
    required this.stream,
    required this.paletteIndex,
    required this.onTap,
  });

  // Палитра иммерсивных плиток — гряда живых окон, как в дизайне §04 E.
  static const List<List<Color>> _palettes = [
    [Color(0xFF2FA84F), Color(0xFF1E88E5)],
    [Color(0xFFFFB547), Color(0xFFFF3B6B)],
    [Color(0xFFFF5A3C), Color(0xFFC04CFD)],
    [Color(0xFF7B61FF), Color(0xFF5DB1FF)],
    [Color(0xFFFF8060), Color(0xFFC04CFD)],
    [Color(0xFF1AC8B8), Color(0xFF5DB1FF)],
  ];

  String _formatViewers(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[paletteIndex % _palettes.length];
    final name = stream.fullName.isNotEmpty ? stream.fullName : stream.username;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // У эфира нет статичного превью — рисуем живое градиентное окно.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: palette,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Нижний скрим + автор.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x80000000)],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                        border: Border.all(color: Colors.white, width: 1.5),
                        image: stream.avatarUrl.isNotEmpty
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(
                                    stream.avatarUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // «Трансляция» бейдж.
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Трансляция',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Число зрителей.
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x6B000000),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsFill.eye,
                        size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      _formatViewers(stream.viewerCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
