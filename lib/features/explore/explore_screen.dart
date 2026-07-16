import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter/services.dart';
import '../../core/analytics/interest_tracker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import '../../core/design/design.dart';
import '../../core/models/explore_item.dart';
import '../../core/models/post.dart';
import '../../core/models/user.dart';
import '../../core/models/live_stream.dart';
import '../../core/providers/explore_feed_provider.dart';
import '../../core/providers/live_streams_provider.dart';
import '../../core/providers/user_provider.dart';
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
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  final _focusNode = FocusNode();
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
    _searchCtrl.dispose();
    _debounce?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(exploreFeedProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      ref.read(searchProvider.notifier).clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim();
      ref.read(searchProvider.notifier).search(q);
      // One event per settled query (not per keystroke). Cap length so we don't
      // store long free text.
      ref.read(interestTrackerProvider).track(
        eventType: 'explore_search',
        entityType: 'query',
        source: 'explore',
        metadata: {'q': q.length > 64 ? q.substring(0, 64) : q},
      );
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(searchProvider.notifier).clear();
    _focusNode.unfocus();
    setState(() => _selectedTab = 0);
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
    final searchState = ref.watch(searchProvider);
    final hasQuery = _searchCtrl.text.trim().isNotEmpty;

    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header + search bar + hint --
            _buildHeader(hasQuery),

            // -- Content --
            Expanded(
              child: hasQuery
                  ? _buildSearchResults(searchState)
                  : _contentForFilter(
                      ref.watch(exploreFeedProvider.select((s) => s.filter))),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Header: title + search bar + privacy hint
  // =========================================================================

  // Search mode tab (search query active)
  int _selectedTab = 0;

  // Browse-mode category chips (no query). Each maps to a BACKEND filter on the
  // unified /explore feed — no client-side composition. People are reached via
  // search, so there is no "Люди" chip here.
  static const List<String> _browseFilters = ['Все', 'Reels', 'Посты', 'Волны', 'Эфиры'];
  static const List<String> _browseFilterKeys = ['all', 'reels', 'posts', 'waves', 'live'];
  // TODO(tags): re-add a 'Теги' tab once the backend supports tag search.
  // The /search endpoint currently returns only {users, posts} (type ∈
  // users|posts|all; anything else is coerced to 'all') and SearchResult has
  // no tags payload — a Теги tab would always drop results, so it is hidden.
  static const List<String> _searchTabs = ['Публикации', 'Аккаунты'];

  Widget _buildHeader(bool hasQuery) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Дизайн-ядро (§04): «Интересное» — про открытие. Крупный серифный
          // заголовок убран, остаётся только kicker и строка поиска, чтобы
          // мозаика дышала и сразу открывалась под рукой.
          Text(
            'ИНТЕРЕСНОЕ',
            style: SeeUTypography.kicker.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 12),

          // Floating frosted-glass search bar (shared design-system component).
          SeeUGlassSearchBar(
            controller: _searchCtrl,
            focusNode: _focusNode,
            hintText: 'Искать людей, звуки, теги',
            onChanged: _onSearchChanged,
            onClear: hasQuery ? _clearSearch : null,
            blur: 28,
          ),

          // Tab row only when searching. Browse mode = single grid of all
          // publications (см. user model: каждая публикация = «рилс»).
          if (hasQuery) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: List.generate(
                  _searchTabs.length,
                  (i) => _filterChip(
                    label: _searchTabs[i],
                    active: _selectedTab == i,
                    onTap: () {
                      setState(() => _selectedTab = i);
                      String searchType;
                      switch (i) {
                        case 0: searchType = 'posts'; break;
                        case 1: searchType = 'users'; break;
                        default: searchType = 'all';
                      }
                      ref.read(searchProvider.notifier).setSearchType(searchType);
                    },
                  ),
                ),
              ),
            ),
          ],

          // Browse-mode category chips (no active search query). Each chip
          // switches the BACKEND filter on the unified Explore feed.
          if (!hasQuery) ...[
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
                    // «Рилс»/«Посты» — не гридовые фильтры, а быстрый переход:
                    // тап сразу открывает полноэкранную видео- / фото-ленту.
                    // Поэтому они не подсвечиваются как активный фильтр грида.
                    final isFeedShortcut = key == 'reels' || key == 'posts';
                    return _filterChip(
                      label: _browseFilters[i],
                      active: !isFeedShortcut && key == activeFilter,
                      showLiveDot: key == 'live',
                      onTap: () {
                        ref.read(interestTrackerProvider).track(
                          eventType: 'explore_filter_select',
                          entityType: 'filter',
                          source: 'explore',
                          metadata: {'filter': key},
                        );
                        if (isFeedShortcut) {
                          final type = key == 'reels' ? 'video' : 'photo';
                          context.push('/view/first?type=$type');
                          return;
                        }
                        ref.read(interestTrackerProvider).resetImpressions();
                        ref.read(exploreFeedProvider.notifier).setFilter(key);
                      },
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Divider(height: 0.5, thickness: 0.5, color: c.line),
        ],
      ),
    );
  }

  /// Editorial glass-style filter pill: active = accent-hairline + soft accent
  /// tint + accent kicker label; inactive = flat surface tint. No per-chip
  /// BackdropFilter (these live in a horizontal scroll strip — keep it cheap).
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? SeeUColors.accent.withValues(alpha: 0.12)
                : c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
              color: active
                  ? SeeUColors.accent.withValues(alpha: 0.55)
                  : c.line,
              width: active ? 1 : 0.5,
            ),
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
                const SizedBox(width: 6),
              ],
              Text(
                label.toUpperCase(),
                style: SeeUTypography.kicker.copyWith(
                  color: active ? SeeUColors.accent : c.ink3,
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

    // Lazy masonry: pre-compute the row-block layout (cheap O(n) index math,
    // no widgets) and let a SliverList build each block on demand. Cells only
    // paint when scrolled into the viewport (± cacheExtent) — Instagram-style.
    const gap = 2.0;
    const padding = 4.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final cellSize = (screenWidth - padding * 2 - gap * 2) / 3;
    final blocks = _computeBlocks(state.items.length);

    return SeeURadarRefresh(
      onRefresh: () => ref.read(exploreFeedProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: padding),
            sliver: SliverList.builder(
              itemCount: blocks.length,
              itemBuilder: (context, blockIndex) => _MasonryRow(
                block: blocks[blockIndex],
                items: state.items,
                cellSize: cellSize,
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
    final itemSize = (MediaQuery.of(context).size.width - 14) / 3;
    return SeeUShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
            mainAxisExtent: itemSize,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Search results
  // =========================================================================

  Widget _buildSearchResults(SearchState searchState) {
    final c = context.seeuColors;
    if (searchState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    // Apply client-side tab filtering
    final filteredUsers = _selectedTab == 1 // Аккаунты: show users
        ? searchState.users
        : <User>[];
    final filteredPosts = _selectedTab == 1 // Аккаунты: hide posts
        ? <Post>[]
        : searchState.posts;

    if (filteredUsers.isEmpty && filteredPosts.isEmpty) {
      return SeeUEmptyState(
        icon: PhosphorIcons.magnifyingGlass(),
        title: 'Ничего не найдено',
        subtitle: 'Попробуйте другой запрос',
      );
    }

    return AnimationLimiter(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (filteredUsers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SeeUSectionHeader(kicker: 'Люди', padding: EdgeInsets.zero),
            ),
            ...List.generate(filteredUsers.length, (index) {
              final user = filteredUsers[index];
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 300),
                child: SlideAnimation(
                  verticalOffset: 20,
                  child: FadeInAnimation(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: _UserSearchCard(user: user),
                    ),
                  ),
                ),
              );
            }),
          ],
          if (filteredPosts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: SeeUSectionHeader(kicker: 'Публикации', padding: EdgeInsets.zero),
            ),
            Builder(builder: (context) {
              // Size disk/mem cache to the actual cell, not full-res.
              // 3 columns, 16px side padding, 4px cross-axis spacing (×2).
              final cellWidth =
                  (MediaQuery.of(context).size.width - 32 - 8) / 3;
              final cacheWidth =
                  (cellWidth * MediaQuery.devicePixelRatioOf(context)).round();
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: filteredPosts.length,
                itemBuilder: (context, index) {
                  final post = filteredPosts[index];
                  final imgUrl = post.gridThumbnailUrl;
                  return GestureDetector(
                    onTap: () => context.push('/post/${post.id}'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                      child: imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: cacheWidth,
                              maxWidthDiskCache: cacheWidth,
                              placeholder: (_, __) =>
                                  Container(color: c.surface2),
                              errorWidget: (_, __, ___) =>
                                  Container(color: c.surface2),
                            )
                          : Container(color: c.surface2),
                    ),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Masonry grid: 3-column, every 7th item spans 2 rows (1:2 ratio).
//
// Layout is now LAZY: the packing is pre-computed into row "blocks" (cheap
// index math, no widgets) and a SliverList builds each block on demand. Each
// cell only paints when scrolled into the viewport (± cacheExtent), and fires
// its impression from a VisibilityDetector instead of inside build().
// ===========================================================================

/// `index`-th item is a 2-row tall tile. SAME rule everywhere — never branch
/// on content type. Kept identical to the original `(index + 3) % 7 == 0`.
bool _isTall(int index) => (index + 3) % 7 == 0;

/// The four row-block shapes the packer can emit. The packer walks items
/// left→right, top→bottom; a tall tile claims its column for two rows and
/// pulls extra normals into the other columns.
enum _BlockType { normal, tall0, tall1, tall2 }

class _RowBlock {
  final _BlockType type;
  final int start;
  const _RowBlock(this.type, this.start);
}

/// Cheap O(n) pass (index math only, no widgets) that mirrors the original
/// eager packing EXACTLY: tall0/normal consume 3 items, tall1/tall2 consume 5.
List<_RowBlock> _computeBlocks(int count) {
  final blocks = <_RowBlock>[];
  int i = 0;
  while (i < count) {
    final tall0 = _isTall(i);
    final tall1 = (i + 1 < count) && _isTall(i + 1);
    final tall2 = (i + 2 < count) && _isTall(i + 2);
    if (tall0) {
      blocks.add(_RowBlock(_BlockType.tall0, i));
      i += 3;
    } else if (tall1) {
      blocks.add(_RowBlock(_BlockType.tall1, i));
      i += 5;
    } else if (tall2) {
      blocks.add(_RowBlock(_BlockType.tall2, i));
      i += 5;
    } else {
      blocks.add(_RowBlock(_BlockType.normal, i));
      i += 3;
    }
  }
  return blocks;
}

/// Builds a single row block on demand. Lives inside a SliverList so only the
/// blocks near the viewport are ever constructed.
class _MasonryRow extends StatelessWidget {
  final _RowBlock block;
  final List<ExploreItem> items;
  final double cellSize;
  final void Function(ExploreItem item) onTapItem;
  final void Function(ExploreItem item)? onImpression;
  final void Function(ExploreItem item)? onLongPressItem;

  const _MasonryRow({
    required this.block,
    required this.items,
    required this.cellSize,
    required this.onTapItem,
    this.onImpression,
    this.onLongPressItem,
  });

  static const double _gap = 2.0;

  Widget _cell(int index) {
    if (index < 0 || index >= items.length) {
      return SizedBox(width: cellSize, height: cellSize);
    }
    return _MasonryCell(
      key: ValueKey('explore_cell_$index'),
      item: items[index],
      index: index,
      cellSize: cellSize,
      onTapItem: onTapItem,
      onImpression: onImpression,
      onLongPressItem: onLongPressItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = block.start;
    late final Widget row;
    switch (block.type) {
      case _BlockType.tall0:
        // Column 0 tall, paired with 2 normals stacked in columns 1+2.
        row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cell(start),
            const SizedBox(width: _gap),
            Column(children: [
              _cell(start + 1),
              const SizedBox(height: _gap),
              _cell(start + 2),
            ]),
          ],
        );
        break;
      case _BlockType.tall1:
        // Column 1 tall, normals stacked in columns 0+2.
        row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              _cell(start),
              const SizedBox(height: _gap),
              _cell(start + 2),
            ]),
            const SizedBox(width: _gap),
            _cell(start + 1),
            const SizedBox(width: _gap),
            Column(children: [
              _cell(start + 3),
              const SizedBox(height: _gap),
              _cell(start + 4),
            ]),
          ],
        );
        break;
      case _BlockType.tall2:
        // Column 2 tall, normals stacked in columns 0+1.
        row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              _cell(start),
              const SizedBox(height: _gap),
              _cell(start + 3),
            ]),
            const SizedBox(width: _gap),
            Column(children: [
              _cell(start + 1),
              const SizedBox(height: _gap),
              _cell(start + 4),
            ]),
            const SizedBox(width: _gap),
            _cell(start + 2),
          ],
        );
        break;
      case _BlockType.normal:
        // All three items 1:1.
        row = Row(
          children: [
            _cell(start),
            if (start + 1 < items.length) ...[
              const SizedBox(width: _gap),
              _cell(start + 1),
            ],
            if (start + 2 < items.length) ...[
              const SizedBox(width: _gap),
              _cell(start + 2),
            ],
          ],
        );
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: row,
    );
  }
}

/// A single masonry cell. Stateful so the impression fires exactly once (when
/// >50% visible) via VisibilityDetector — not as a build-time side effect.
class _MasonryCell extends StatefulWidget {
  final ExploreItem item;
  final int index;
  final double cellSize;
  final void Function(ExploreItem item) onTapItem;
  final void Function(ExploreItem item)? onImpression;
  final void Function(ExploreItem item)? onLongPressItem;

  const _MasonryCell({
    super.key,
    required this.item,
    required this.index,
    required this.cellSize,
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

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final item = widget.item;
    final cellSize = widget.cellSize;
    final isShort = item.type == ExploreItemType.short;
    final isVideo = item.type == ExploreItemType.video;
    final showPlay = isShort || isVideo || item.isVideoPost;
    final imageUrl = item.displayImage;
    final count = item.likesCount > 0 ? item.likesCount : item.viewsCount;
    // The 2-row span decision uses the SAME rule as the packer, never per-type.
    final isTall = _isTall(widget.index);
    final height = isTall ? cellSize * 2 + 2 : cellSize;
    // Decode/cache at cell resolution (~screenWidth/3), NOT full-res.
    final cacheWidth =
        (cellSize * MediaQuery.devicePixelRatioOf(context)).round();

    return GestureDetector(
      onTap: () => widget.onTapItem(item),
      onLongPress: widget.onLongPressItem == null
          ? null
          : () => widget.onLongPressItem!(item),
      child: VisibilityDetector(
        key: ValueKey('explore_vis_${widget.index}'),
        onVisibilityChanged: _onVisibility,
        child: SizedBox(
          width: cellSize,
          height: height,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SeeURadii.small),
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
                    showPlay ? PhosphorIcons.playCircle() : PhosphorIcons.image(),
                    color: c.ink3,
                  ),
                ),
              // Play badge top-right for shorts/videos/video-posts.
              if (showPlay)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    PhosphorIcons.play(PhosphorIconsStyle.fill),
                    color: Colors.white,
                    size: 16,
                    shadows: const [
                      Shadow(color: SeeUColors.mediumScrim, blurRadius: 4),
                    ],
                  ),
                ),
              // HD badge for normal videos with a ≥720p frame.
              if (isVideo && item.height >= 720)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: SeeUColors.mediumScrim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('HD',
                        style: SeeUTypography.micro.copyWith(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              // Engagement count overlay for play items.
              if (showPlay && count > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 5),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SeeUColors.transparentBlack,
                          SeeUColors.mediumScrim,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.likesCount > 0
                              ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                              : PhosphorIcons.play(PhosphorIconsStyle.fill),
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          count >= 1000
                              ? '${(count / 1000).toStringAsFixed(1)}k'
                              : '$count',
                          style: SeeUTypography.micro.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: const [
                              Shadow(color: SeeUColors.mediumScrim, blurRadius: 3),
                            ],
                          ),
                        ),
                      ],
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
// User search result card
// ===========================================================================

class _UserSearchCard extends StatelessWidget {
  final User user;
  const _UserSearchCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => context.push('/profile/${user.username}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.surface2,
              backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                  ? Text(
                      user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                      style: SeeUTypography.subtitle,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            color: SeeUColors.accent, size: 14),
                      ],
                    ],
                  ),
                  Text(
                    user.fullName,
                    style: SeeUTypography.caption.copyWith(color: c.ink3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
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
