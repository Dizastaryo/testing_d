import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/models/user.dart';
import '../../core/providers/user_provider.dart';

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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      ref.read(searchProvider.notifier).clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchProvider.notifier).search(value.trim());
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(searchProvider.notifier).clear();
    _focusNode.unfocus();
    setState(() {});
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
                  : _selectedTab == 3
                      ? _buildAudioTab()
                      : _selectedTab == 4
                          ? _buildTagsTab()
                          : _buildMixedGrid(),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Header: title + search bar + privacy hint
  // =========================================================================

  // Tab index for explore tabs
  int _selectedTab = 0;
  static const List<String> _exploreTabs = [
    'Всё', 'Reels', 'Люди', 'Аудио', 'Теги',
  ];

  Widget _buildHeader(bool hasQuery) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 58, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serif "Поиск" title
          Text(
            'Поиск',
            style: SeeUTypography.displayL.copyWith(
              height: 1.0,
              letterSpacing: -0.64,
            ),
          ),
          const SizedBox(height: 12),

          // Search bar: height 44, surface2 bg, borderRadius pill
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(color: c.line, width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  PhosphorIcons.magnifyingGlass(),
                  size: 18,
                  color: c.ink3,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    style: SeeUTypography.body.copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'Искать людей, звуки, теги',
                      hintStyle: SeeUTypography.body.copyWith(
                        fontSize: 14,
                        color: c.ink3,
                      ),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (hasQuery)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c.ink3.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(PhosphorIcons.x(),
                            size: 12, color: c.ink2),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Tab row: Всё | Reels | Люди | Аудио | Теги
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(_exploreTabs.length, (i) {
                final isActive = _selectedTab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedTab = i);
                      // Map tab index to search type for backend filtering
                      String searchType;
                      switch (i) {
                        case 1: // Reels
                          searchType = 'posts';
                          break;
                        case 2: // Люди
                          searchType = 'users';
                          break;
                        default:
                          searchType = 'all';
                      }
                      ref.read(searchProvider.notifier).setSearchType(searchType);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isActive
                            ? c.ink
                            : c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      child: Text(
                        _exploreTabs[i],
                        style: SeeUTypography.caption.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isActive ? Colors.white : c.ink2,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // =========================================================================
  // Audio tab
  // =========================================================================

  Widget _buildAudioTab() {
    final c = context.seeuColors;
    final audioAsync = ref.watch(audioTracksProvider);

    return audioAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить', style: SeeUTypography.body.copyWith(color: c.ink2)),
            const SizedBox(height: 12),
            SeeUButton(
              label: 'Повторить',
              variant: SeeUButtonVariant.primary,
              width: 120,
              height: 44,
              onTap: () => ref.refresh(audioTracksProvider),
            ),
          ],
        ),
      ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.musicNotes(), size: 48, color: c.ink3),
                const SizedBox(height: 12),
                Text('Нет аудио', style: SeeUTypography.body.copyWith(color: c.ink2)),
              ],
            ),
          );
        }

        return AnimationLimiter(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 300),
                child: SlideAnimation(
                  verticalOffset: 20,
                  child: FadeInAnimation(
                    child: _AudioTrackCard(track: track),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================================
  // Tags tab
  // =========================================================================

  Widget _buildTagsTab() {
    final c = context.seeuColors;
    final tagsAsync = ref.watch(trendingTagsProvider);

    return tagsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить', style: SeeUTypography.body.copyWith(color: c.ink2)),
            const SizedBox(height: 12),
            SeeUButton(
              label: 'Повторить',
              variant: SeeUButtonVariant.primary,
              width: 120,
              height: 44,
              onTap: () => ref.refresh(trendingTagsProvider),
            ),
          ],
        ),
      ),
      data: (tags) {
        if (tags.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.hash(), size: 48, color: c.ink3),
                const SizedBox(height: 12),
                Text('Нет тегов', style: SeeUTypography.body.copyWith(color: c.ink2)),
              ],
            ),
          );
        }

        return AnimationLimiter(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 250),
                child: SlideAnimation(
                  verticalOffset: 16,
                  child: FadeInAnimation(
                    child: _TagCard(
                      tag: tag,
                      onTap: () {
                        _searchCtrl.text = '#${tag.tag}';
                        _onSearchChanged('#${tag.tag}');
                        setState(() {});
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================================
  // Mixed grid: tags + masonry posts grid
  // =========================================================================

  // Tags section removed - all content comes from backend search

  Widget _buildMixedGrid() {
    final c = context.seeuColors;
    final postsAsync = ref.watch(explorePostsProvider);

    return postsAsync.when(
      loading: () => _buildGridShimmer(),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(),
                size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить',
              style: SeeUTypography.body
                  .copyWith(color: c.ink2),
            ),
            const SizedBox(height: 12),
            SeeUButton(
              label: 'Повторить',
              variant: SeeUButtonVariant.primary,
              width: 120,
              height: 44,
              onTap: () => ref.refresh(explorePostsProvider),
            ),
          ],
        ),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return Center(
            child: Text(
              'Нет публикаций',
              style: SeeUTypography.body
                  .copyWith(color: c.ink2),
            ),
          );
        }

        final displayPosts = posts.take(18).toList();
        final rng = Random(42);

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // Tags section as a sliver header
            // Tags section removed - search handles filtering

            // 3-column masonry grid (every 7th item is 1:2, spans 2 rows)
            SliverToBoxAdapter(
              child: _MasonryGrid(
                posts: displayPosts,
                rng: rng,
                onTapPost: (index) {
                  final post = displayPosts[index];
                  final isVideo = post.media.any((m) => m.type == MediaType.video);
                  if (isVideo) {
                    context.push('/reels');
                  } else {
                    context.push('/post/${post.id}');
                  }
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
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
              borderRadius: BorderRadius.circular(10),
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
    final filteredUsers = _selectedTab == 1 // Reels tab: no users
        ? <User>[]
        : searchState.users;
    final filteredPosts = _selectedTab == 1 // Reels tab: only video posts
        ? searchState.posts
            .where((p) => p.media.any((m) => m.type == MediaType.video))
            .toList()
        : _selectedTab == 2 // Люди tab: no posts
            ? <Post>[]
            : searchState.posts;

    if (filteredUsers.isEmpty && filteredPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.magnifyingGlass(),
                size: 56, color: c.ink3),
            const SizedBox(height: 16),
            Text('\u041D\u0438\u0447\u0435\u0433\u043E \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D\u043E', style: SeeUTypography.title),
            const SizedBox(height: 6),
            Text(
              '\u041F\u043E\u043F\u0440\u043E\u0431\u0443\u0439\u0442\u0435 \u0434\u0440\u0443\u0433\u043E\u0439 \u0437\u0430\u043F\u0440\u043E\u0441',
              style: SeeUTypography.body
                  .copyWith(color: c.ink2),
            ),
          ],
        ),
      );
    }

    return AnimationLimiter(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          if (filteredUsers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('\u041B\u044E\u0434\u0438', style: SeeUTypography.title),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('\u041F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u0438', style: SeeUTypography.title),
            ),
            GridView.builder(
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
                final imgUrl = post.media.isNotEmpty ? post.media.first.url : '';
                return GestureDetector(
                  onTap: () {
                    final isVideo = post.media.any((m) => m.type == MediaType.video);
                    if (isVideo) {
                      context.push('/reels');
                    } else {
                      context.push('/post/${post.id}');
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imgUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imgUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: c.surface2),
                            errorWidget: (_, __, ___) =>
                                Container(color: c.surface2),
                          )
                        : Container(color: c.surface2),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Masonry grid widget: 3-column, every 7th item spans 2 rows (1:2 ratio)
// ===========================================================================

class _MasonryGrid extends StatelessWidget {
  final List<Post> posts;
  final Random rng;
  final void Function(int index) onTapPost;

  const _MasonryGrid({
    required this.posts,
    required this.rng,
    required this.onTapPost,
  });

  Widget _buildCell(BuildContext context, int index, double cellSize) {
    final c = context.seeuColors;
    final post = posts[index];
    final imageUrl = post.media.isNotEmpty ? post.media.first.url : '';
    final likeCount = post.likesCount;
    final isTall = (index + 3) % 7 == 0;
    final isReel = post.media.any((m) => m.type == MediaType.video);
    final height = isTall ? cellSize * 2 + 2 : cellSize;

    return GestureDetector(
      onTap: () => onTapPost(index),
      child: SizedBox(
        width: cellSize,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: c.surface2),
                errorWidget: (_, __, ___) => Container(
                  color: c.surface2,
                  child: Icon(PhosphorIcons.image(),
                      color: c.ink3),
                ),
              ),
              // Reel: play icon top-right + view count bottom-left
              if (isReel) ...[
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    PhosphorIcons.play(PhosphorIconsStyle.fill),
                    color: Colors.white,
                    size: 16,
                    shadows: const [
                      Shadow(
                        color: Color(0x80000000),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.play(PhosphorIconsStyle.fill),
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          likeCount >= 1000
                              ? '${(likeCount / 1000).toStringAsFixed(1)}k'
                              : '$likeCount',
                          style: SeeUTypography.micro.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: const [
                              Shadow(
                                  color: Color(0x80000000), blurRadius: 3),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (post.media.length > 1)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
                    color: Colors.white,
                    size: 14,
                    shadows: const [
                      Shadow(
                        color: Color(0x80000000),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = 2.0;
    const padding = 4.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final cellSize = (screenWidth - padding * 2 - gap * 2) / 3;

    // Build rows manually so every 7th item can span 2 rows.
    // We lay out items in 3-column order; a tall item occupies its column
    // for 2 row-heights while the other 2 columns fill with 2 normal items.
    final List<Widget> rows = [];
    int i = 0;
    while (i < posts.length) {
      // Determine if any of the next 3 items is tall
      final i0 = i;
      final i1 = i + 1 < posts.length ? i + 1 : -1;
      final i2 = i + 2 < posts.length ? i + 2 : -1;

      final tall0 = (i0 + 3) % 7 == 0;
      final tall1 = i1 != -1 && (i1 + 3) % 7 == 0;
      final tall2 = i2 != -1 && (i2 + 3) % 7 == 0;

      if (tall0) {
        // Column 0 is tall — pair it with 2 normal rows in columns 1 & 2
        final topLeft = _buildCell(context, i0, cellSize);
        final topRight = i1 != -1
            ? _buildCell(context, i1, cellSize)
            : SizedBox(width: cellSize, height: cellSize);
        final botRight = i2 != -1
            ? _buildCell(context, i2, cellSize)
            : SizedBox(width: cellSize, height: cellSize);

        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                topLeft,
                const SizedBox(width: gap),
                Column(
                  children: [
                    topRight,
                    const SizedBox(height: gap),
                    botRight,
                  ],
                ),
              ],
            ),
          ),
        );
        i += 3;
      } else if (tall1) {
        // Column 1 is tall — pair with normals in columns 0 & 2
        final col0top = _buildCell(context, i0, cellSize);
        final col1 = _buildCell(context, i1, cellSize);
        final col0bot = i2 != -1
            ? _buildCell(context, i2, cellSize)
            : SizedBox(width: cellSize, height: cellSize);
        final col2top = i + 3 < posts.length
            ? _buildCell(context, i + 3, cellSize)
            : SizedBox(width: cellSize, height: cellSize);
        final col2bot = i + 4 < posts.length
            ? _buildCell(context, i + 4, cellSize)
            : SizedBox(width: cellSize, height: cellSize);

        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [col0top, const SizedBox(height: gap), col0bot]),
                const SizedBox(width: gap),
                col1,
                const SizedBox(width: gap),
                Column(children: [col2top, const SizedBox(height: gap), col2bot]),
              ],
            ),
          ),
        );
        i += 5;
      } else if (tall2) {
        // Column 2 is tall — pair with normals in columns 0 & 1
        final col0top = _buildCell(context, i0, cellSize);
        final col1top = i1 != -1
            ? _buildCell(context, i1, cellSize)
            : SizedBox(width: cellSize, height: cellSize);
        final col2 = _buildCell(context, i2, cellSize);
        final col0bot = i + 3 < posts.length
            ? _buildCell(context, i + 3, cellSize)
            : SizedBox(width: cellSize, height: cellSize);
        final col1bot = i + 4 < posts.length
            ? _buildCell(context, i + 4, cellSize)
            : SizedBox(width: cellSize, height: cellSize);

        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [col0top, const SizedBox(height: gap), col0bot]),
                const SizedBox(width: gap),
                Column(children: [col1top, const SizedBox(height: gap), col1bot]),
                const SizedBox(width: gap),
                col2,
              ],
            ),
          ),
        );
        i += 5;
      } else {
        // Normal row: all 3 items are 1:1
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              children: [
                _buildCell(context, i0, cellSize),
                if (i1 != -1) ...[
                  const SizedBox(width: gap),
                  _buildCell(context, i1, cellSize),
                ],
                if (i2 != -1) ...[
                  const SizedBox(width: gap),
                  _buildCell(context, i2, cellSize),
                ],
              ],
            ),
          ),
        );
        i += 3;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: padding),
      child: Column(children: rows),
    );
  }
}

// ===========================================================================
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
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
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

class _AudioTrackCard extends StatelessWidget {
  final AudioTrack track;
  const _AudioTrackCard({required this.track});

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatUses(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Row(
          children: [
            // Cover art
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: c.surface2,
                          child: Icon(PhosphorIcons.musicNotes(),
                              color: c.ink3, size: 24),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: c.surface2,
                          child: Icon(PhosphorIcons.musicNotes(),
                              color: c.ink3, size: 24),
                        ),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIcons.musicNotes(),
                            color: c.ink3, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Title + artist + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: SeeUTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: SeeUTypography.caption.copyWith(color: c.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(PhosphorIcons.play(PhosphorIconsStyle.fill),
                          size: 11, color: c.ink3),
                      const SizedBox(width: 3),
                      Text(
                        _formatUses(track.usesCount),
                        style: SeeUTypography.micro.copyWith(
                          color: c.ink3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(PhosphorIcons.clock(), size: 11, color: c.ink3),
                      const SizedBox(width: 3),
                      Text(
                        _formatDuration(track.durationSeconds),
                        style: SeeUTypography.micro.copyWith(color: c.ink3),
                      ),
                      if (track.genre.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            track.genre,
                            style: SeeUTypography.micro.copyWith(
                              color: SeeUColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Play button
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.play(PhosphorIconsStyle.fill),
                size: 16,
                color: SeeUColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Tag card
// ===========================================================================

class _TagCard extends StatelessWidget {
  final TrendingTag tag;
  final VoidCallback onTap;
  const _TagCard({required this.tag, required this.onTap});

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М публ.';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К публ.';
    return '$n публ.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '#',
                    style: SeeUTypography.title.copyWith(
                      color: SeeUColors.accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${tag.tag}',
                      style: SeeUTypography.subtitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatCount(tag.postsCount),
                      style: SeeUTypography.caption.copyWith(color: c.ink3),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIcons.caretRight(),
                size: 18,
                color: c.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

