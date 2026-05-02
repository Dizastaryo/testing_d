import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/design/design.dart';
import '../../core/models/user.dart';
import '../../core/models/post.dart';
import '../../core/providers/user_provider.dart';
import '../feed/widgets/post_card.dart';

// ---------------------------------------------------------------------------
// Mock Reels data
// ---------------------------------------------------------------------------

class _MockReel {
  final String id;
  final String imageUrl;
  final String description;
  final User author;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  bool isLiked;
  bool isSaved;

  _MockReel({
    required this.id,
    required this.imageUrl,
    required this.description,
    required this.author,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.shareCount,
    this.isLiked = false,
    this.isSaved = false,
  });
}

final _reelRng = Random(99);

List<User> get _reelAuthors {
  final base = <User>[];
  return [
    ...base,
    User(
      id: 'r1',
      username: 'almaty_life',
      fullName: '\u0410\u0439\u0434\u0430\u043D \u041A\u0430\u0441\u044B\u043C\u043E\u0432',
      bio: '\u0410\u043B\u043C\u0430\u0442\u044B \u0433\u043B\u0430\u0437\u0430\u043C\u0438 \u043C\u0435\u0441\u0442\u043D\u044B\u0445',
      avatarUrl: 'https://i.pravatar.cc/150?img=30',
      followersCount: 24000,
      isVerified: true,
      createdAt: DateTime(2022, 3, 1),
    ),
    User(
      id: 'r2',
      username: 'dana_cook',
      fullName: '\u0414\u0430\u043D\u0430 \u041D\u0443\u0440\u043B\u0430\u043D\u043E\u0432\u0430',
      bio: '\u0420\u0435\u0446\u0435\u043F\u0442\u044B \u043A\u0430\u0436\u0434\u044B\u0439 \u0434\u0435\u043D\u044C',
      avatarUrl: 'https://i.pravatar.cc/150?img=32',
      followersCount: 18500,
      createdAt: DateTime(2022, 7, 10),
    ),
    User(
      id: 'r3',
      username: 'arman_fit',
      fullName: '\u0410\u0440\u043C\u0430\u043D \u0411\u0430\u0439\u043C\u0443\u0440\u0430\u0442\u043E\u0432',
      bio: '\u0424\u0438\u0442\u043D\u0435\u0441-\u0442\u0440\u0435\u043D\u0435\u0440',
      avatarUrl: 'https://i.pravatar.cc/150?img=55',
      followersCount: 9300,
      createdAt: DateTime(2023, 1, 5),
    ),
  ];
}

final List<String> _reelDescriptions = [
  '\u0412\u0435\u0447\u0435\u0440\u043D\u0438\u0439 \u0410\u043B\u043C\u0430\u0442\u044B \uD83C\uDF06',
  '\u0420\u0435\u0446\u0435\u043F\u0442 \u0434\u043D\u044F: \u043D\u0430\u0443\u0440\u044B\u0437 \u043A\u04E9\u0436\u0435 \uD83C\uDF5C',
  '\u0422\u0440\u0435\u043D\u0438\u0440\u043E\u0432\u043A\u0430 \u043D\u0430 \u0440\u0430\u0441\u0441\u0432\u0435\u0442\u0435 \uD83D\uDCAA',
  '\u041B\u0443\u0447\u0448\u0438\u0435 \u043A\u0430\u0444\u0435 \u0433\u043E\u0440\u043E\u0434\u0430 \u2615',
  '\u041F\u0443\u0442\u0435\u0448\u0435\u0441\u0442\u0432\u0438\u0435 \u043D\u0430 \u0411\u0438\u0433 \u0410\u043B\u043C\u0430\u0442\u0438\u043D\u0441\u043A\u043E\u0435 \u043E\u0437\u0435\u0440\u043E \uD83C\uDF0A',
  '\u041C\u043E\u0439 \u0443\u0442\u0440\u0435\u043D\u043D\u0438\u0439 \u0440\u0438\u0442\u0443\u0430\u043B \u2728',
  '\u0421\u0442\u0440\u0438\u0442-\u0444\u0443\u0434 \u0432 \u0410\u0441\u0442\u0430\u043D\u0435 \uD83C\uDF2E',
  '\u041A\u0430\u043A \u044F \u043D\u0430\u0447\u0430\u043B \u0431\u0435\u0433\u0430\u0442\u044C \u043A\u0430\u0436\u0434\u044B\u0439 \u0434\u0435\u043D\u044C \uD83C\uDFC3',
  '\u0417\u0438\u043C\u043D\u0438\u0439 \u0428\u044B\u043C\u0431\u0443\u043B\u0430\u043A \u26F7\uFE0F',
  '\u0414\u043E\u043C\u0430\u0448\u043D\u0438\u0439 \u0431\u0435\u0448\u0431\u0430\u0440\u043C\u0430\u043A \uD83E\uDD69',
  '\u042F\u0440\u043A\u0438\u0435 \u043A\u0440\u0430\u0441\u043A\u0438 \u041A\u043E\u043A-\u0422\u043E\u0431\u0435 \uD83C\uDFA8',
  '\u0413\u043E\u0442\u043E\u0432\u043B\u044E \u0431\u0430\u0443\u0440\u0441\u0430\u043A\u0438 \u043F\u043E \u0440\u0435\u0446\u0435\u043F\u0442\u0443 \u0431\u0430\u0431\u0443\u0448\u043A\u0438 \uD83E\uDD5F',
  '\u0419\u043E\u0433\u0430 \u043D\u0430 \u043A\u0440\u044B\u0448\u0435 \uD83E\uDDD8',
  '\u041D\u043E\u0447\u043D\u043E\u0439 \u0410\u043B\u043C\u0430\u0442\u044B \u0441 \u0434\u0440\u043E\u043D\u0430 \uD83C\uDF03',
  '\u041C\u0430\u0441\u0442\u0435\u0440-\u043A\u043B\u0430\u0441\u0441: \u043B\u0430\u0442\u0442\u0435-\u0430\u0440\u0442 \u2615\uFE0F',
];

List<_MockReel> _generateMockReels() {
  final authors = _reelAuthors;
  return List.generate(15, (i) {
    return _MockReel(
      id: 'reel_$i',
      imageUrl: 'https://picsum.photos/seed/reel_$i/400/700',
      description: _reelDescriptions[i],
      author: authors[i % authors.length],
      viewCount: (_reelRng.nextInt(500) + 1) * 1000 + _reelRng.nextInt(999),
      likeCount: _reelRng.nextInt(50000) + 500,
      commentCount: _reelRng.nextInt(3000) + 50,
      shareCount: _reelRng.nextInt(1000) + 10,
      isLiked: _reelRng.nextBool(),
      isSaved: false,
    );
  });
}

String _formatCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  } else if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return count.toString();
}

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
  late final List<_MockReel> _mockReels;

  @override
  void initState() {
    super.initState();
    _mockReels = _generateMockReels();
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

    return Scaffold(
      backgroundColor: SeeUColors.background,
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

  Widget _buildHeader(bool hasQuery) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 58, 18, 12),
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
          const SizedBox(height: 14),

          // Search bar: height 44, surface2 bg, borderRadius 14
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: SeeUColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  PhosphorIcons.magnifyingGlass(),
                  size: 18,
                  color: SeeUColors.textTertiary,
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
                      hintText: 'Поиск только по @никнейму',
                      hintStyle: SeeUTypography.body.copyWith(
                        fontSize: 14,
                        color: SeeUColors.textTertiary,
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
                          color: SeeUColors.textTertiary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(PhosphorIcons.x(),
                            size: 12, color: SeeUColors.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Lock icon + privacy hint
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.lock(),
                  size: 11,
                  color: SeeUColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Реальные имена не индексируются',
                  style: SeeUTypography.micro.copyWith(
                    fontSize: 11,
                    color: SeeUColors.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Keep the old name so the build method can call either; delegate to header.
  // =========================================================================
  // Mixed grid: tags + masonry posts grid
  // =========================================================================

  static const List<String> _popularTags = [
    '#алматы', '#утро', '#горы', '#тыньшань', '#кафе', '#свет', '#портреты',
  ];

  Widget _buildTagsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "ПОПУЛЯРНОЕ СЕЙЧАС" mono label
          Text(
            'ПОПУЛЯРНОЕ СЕЙЧАС',
            style: SeeUTypography.monoLabel.copyWith(
              letterSpacing: 1.0,
              color: SeeUColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          // Horizontal scrollable tag pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _popularTags.map((tag) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: SeeUColors.surface,
                      borderRadius:
                          BorderRadius.circular(SeeURadii.pill),
                      border: Border.all(
                        color: SeeUColors.borderSubtle,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: SeeUTypography.caption.copyWith(
                        fontSize: 13,
                        color: SeeUColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMixedGrid() {
    final postsAsync = ref.watch(explorePostsProvider);

    return postsAsync.when(
      loading: () => _buildGridShimmer(),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(),
                size: 48, color: SeeUColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить',
              style: SeeUTypography.body
                  .copyWith(color: SeeUColors.textSecondary),
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
                  .copyWith(color: SeeUColors.textSecondary),
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
            SliverToBoxAdapter(child: _buildTagsSection()),

            // 3-column masonry grid (every 7th item is 1:2, spans 2 rows)
            SliverToBoxAdapter(
              child: _MasonryGrid(
                posts: displayPosts,
                rng: rng,
                onTapPost: (index) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ExplorePostsFeed(
                        posts: displayPosts,
                        initialIndex: index,
                      ),
                    ),
                  );
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
  // Reels grid (2 columns, tall thumbnails)
  // =========================================================================

  // _buildReelsGrid removed — reels tab not present in current design.
  // ignore: unused_element
  Widget _buildReelsGrid() {
    return AnimationLimiter(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 120),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 9 / 16,
        ),
        itemCount: _mockReels.length,
        itemBuilder: (context, index) {
          final reel = _mockReels[index];

          return AnimationConfiguration.staggeredGrid(
            position: index,
            columnCount: 2,
            duration: const Duration(milliseconds: 350),
            child: ScaleAnimation(
              scale: 0.93,
              child: FadeInAnimation(
                child: Tappable.scaled(
                  scaleFactor: 0.95,
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => _ReelsViewer(
                          reels: _mockReels,
                          initialIndex: index,
                        ),
                        transitionsBuilder: (_, anim, __, child) {
                          return FadeTransition(opacity: anim, child: child);
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: SeeUShadows.sm,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Thumbnail image
                        CachedNetworkImage(
                          imageUrl: reel.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: SeeUColors.surfaceElevated,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SeeUColors.accent,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: SeeUColors.surfaceElevated,
                            child: Icon(PhosphorIcons.videoCamera(),
                                size: 32, color: SeeUColors.textTertiary),
                          ),
                        ),

                        // Dark gradient overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.4, 1.0],
                                colors: [
                                  Colors.black.withValues(alpha: 0.15),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Play icon center
                        Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),

                        // Bottom info: author + views
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Author
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: reel.author.avatarUrl !=
                                            null
                                        ? CachedNetworkImageProvider(
                                            reel.author.avatarUrl!)
                                        : null,
                                    backgroundColor: Colors.white24,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      reel.author.username,
                                      style: SeeUTypography.caption.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Views
                              Row(
                                children: [
                                  Icon(
                                    PhosphorIcons.play(
                                        PhosphorIconsStyle.fill),
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatCount(reel.viewCount),
                                    style: SeeUTypography.micro.copyWith(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // Grid shimmer (loading state)
  // =========================================================================

  Widget _buildGridShimmer() {
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
              color: SeeUColors.surfaceElevated,
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
    if (searchState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    if (searchState.users.isEmpty && searchState.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.magnifyingGlass(),
                size: 56, color: SeeUColors.textTertiary),
            const SizedBox(height: 16),
            Text('\u041D\u0438\u0447\u0435\u0433\u043E \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D\u043E', style: SeeUTypography.title),
            const SizedBox(height: 6),
            Text(
              '\u041F\u043E\u043F\u0440\u043E\u0431\u0443\u0439\u0442\u0435 \u0434\u0440\u0443\u0433\u043E\u0439 \u0437\u0430\u043F\u0440\u043E\u0441',
              style: SeeUTypography.body
                  .copyWith(color: SeeUColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return AnimationLimiter(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          if (searchState.users.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('\u041B\u044E\u0434\u0438', style: SeeUTypography.title),
            ),
            ...List.generate(searchState.users.length, (index) {
              final user = searchState.users[index];
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
          if (searchState.posts.isNotEmpty) ...[
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
              itemCount: searchState.posts.length,
              itemBuilder: (context, index) {
                final post = searchState.posts[index];
                return GestureDetector(
                  onTap: () => context.push('/post/${post.id}'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: post.media.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: post.media.first.url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: SeeUColors.surfaceElevated),
                            errorWidget: (_, __, ___) =>
                                Container(color: SeeUColors.surfaceElevated),
                          )
                        : Container(color: SeeUColors.surfaceElevated),
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
    final post = posts[index];
    final imageUrl = post.media.isNotEmpty
        ? post.media.first.url
        : 'https://picsum.photos/seed/explore_$index/400/400';
    final likeCount = rng.nextInt(500) + 10;
    final isTall = index % 7 == 0;
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
                    Container(color: SeeUColors.surfaceElevated),
                errorWidget: (_, __, ___) => Container(
                  color: SeeUColors.surfaceElevated,
                  child: Icon(PhosphorIcons.image(),
                      color: SeeUColors.textTertiary),
                ),
              ),
              // Bottom gradient with like count
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
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
                        PhosphorIcons.heart(PhosphorIconsStyle.fill),
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$likeCount',
                        style: SeeUTypography.micro.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (post.media.length > 1)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
                    color: Colors.white,
                    size: 14,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
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

      final tall0 = i0 % 7 == 0;
      final tall1 = i1 != -1 && i1 % 7 == 0;
      final tall2 = i2 != -1 && i2 % 7 == 0;

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
// Explore Posts Feed (opened when tapping a post in grid)
// ===========================================================================

class _ExplorePostsFeed extends ConsumerStatefulWidget {
  final List<Post> posts;
  final int initialIndex;

  const _ExplorePostsFeed({
    required this.posts,
    required this.initialIndex,
  });

  @override
  ConsumerState<_ExplorePostsFeed> createState() => _ExplorePostsFeedState();
}

class _ExplorePostsFeedState extends ConsumerState<_ExplorePostsFeed> {
  late final ScrollController _scrollController;
  final GlobalKey _targetKey = GlobalKey();
  bool _didScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use post-frame callback to scroll to the initial item
    if (!_didScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_targetKey.currentContext != null && mounted) {
          Scrollable.ensureVisible(
            _targetKey.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          _didScroll = true;
        }
      });
    }

    return Scaffold(
      backgroundColor: SeeUColors.background,
      appBar: AppBar(
        backgroundColor: SeeUColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold),
              color: SeeUColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '\u041F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u0438',
          style: SeeUTypography.title,
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: widget.posts.length,
        itemBuilder: (context, index) {
          final post = widget.posts[index];
          return Container(
            key: index == widget.initialIndex ? _targetKey : null,
            child: PostCard(post: post),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Reels Viewer (fullscreen TikTok-style)
// ===========================================================================

class _ReelsViewer extends StatefulWidget {
  final List<_MockReel> reels;
  final int initialIndex;

  const _ReelsViewer({
    required this.reels,
    required this.initialIndex,
  });

  @override
  State<_ReelsViewer> createState() => _ReelsViewerState();
}

class _ReelsViewerState extends State<_ReelsViewer>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;

  // Heart animation
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnim;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimController);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _heartAnimController.dispose();
    super.dispose();
  }

  void _onDoubleTap(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      widget.reels[index].isLiked = true;
      _showHeart = true;
    });
    _heartAnimController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _toggleLike(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      widget.reels[index].isLiked = !widget.reels[index].isLiked;
    });
  }

  void _toggleSave(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      widget.reels[index].isSaved = !widget.reels[index].isSaved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Page view
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemCount: widget.reels.length,
            itemBuilder: (context, index) {
              final reel = widget.reels[index];
              return GestureDetector(
                onDoubleTap: () => _onDoubleTap(index),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background image
                    CachedNetworkImage(
                      imageUrl: reel.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.black,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SeeUColors.accent,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[900],
                        child: const Icon(Icons.broken_image,
                            color: Colors.white38, size: 48),
                      ),
                    ),

                    // Dark gradient overlay for readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.3, 0.7, 1.0],
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Right side action buttons
                    Positioned(
                      right: 12,
                      bottom: 140,
                      child: _buildActionButtons(reel, index),
                    ),

                    // Bottom left: author info + description
                    Positioned(
                      left: 16,
                      right: 80,
                      bottom: 60,
                      child: _buildBottomInfo(reel),
                    ),

                    // Bottom: mock progress bar
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildProgressBar(),
                    ),

                    // Double-tap heart animation
                    if (_showHeart && index == _currentIndex)
                      Center(
                        child: AnimatedBuilder(
                          animation: _heartScaleAnim,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _heartScaleAnim.value,
                              child: Icon(
                                PhosphorIcons.heart(PhosphorIconsStyle.fill),
                                size: 100,
                                color: Colors.white.withValues(alpha: 0.9),
                                shadows: [
                                  Shadow(
                                    color:
                                        SeeUColors.accent.withValues(alpha: 0.6),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // Top bar: back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _buildTopBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildActionButtons(_MockReel reel, int index) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like
        _ReelActionButton(
          icon: reel.isLiked
              ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
              : PhosphorIcons.heart(),
          label: _formatCount(reel.likeCount + (reel.isLiked ? 1 : 0)),
          color: reel.isLiked ? SeeUColors.like : Colors.white,
          onTap: () => _toggleLike(index),
        ),
        const SizedBox(height: 20),

        // Comment
        _ReelActionButton(
          icon: PhosphorIcons.chatCircle(),
          label: _formatCount(reel.commentCount),
          color: Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            _showCommentsSheet(context, reel);
          },
        ),
        const SizedBox(height: 20),

        // Share
        _ReelActionButton(
          icon: PhosphorIcons.shareFat(),
          label: _formatCount(reel.shareCount),
          color: Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            _showShareSheet(context);
          },
        ),
        const SizedBox(height: 20),

        // Bookmark
        _ReelActionButton(
          icon: reel.isSaved
              ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
              : PhosphorIcons.bookmarkSimple(),
          label: '',
          color: reel.isSaved ? SeeUColors.accent : Colors.white,
          onTap: () => _toggleSave(index),
        ),
      ],
    );
  }

  Widget _buildBottomInfo(_MockReel reel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Author row
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: reel.author.avatarUrl != null
                  ? CachedNetworkImageProvider(reel.author.avatarUrl!)
                  : null,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        reel.author.username,
                        style: SeeUTypography.subtitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (reel.author.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    reel.author.fullName,
                    style: SeeUTypography.micro.copyWith(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Follow button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: Text(
                '\u041F\u043E\u0434\u043F\u0438\u0441\u0430\u0442\u044C\u0441\u044F',
                style: SeeUTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Description
        Text(
          reel.description,
          style: SeeUTypography.body.copyWith(
            color: Colors.white,
            fontSize: 14,
            height: 1.4,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // Views count
        Row(
          children: [
            Icon(PhosphorIcons.eye(), size: 14, color: Colors.white60),
            const SizedBox(width: 4),
            Text(
              '${_formatCount(reel.viewCount)} \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u043E\u0432',
              style: SeeUTypography.micro.copyWith(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 3,
      margin: const EdgeInsets.only(bottom: 34),
      child: LinearProgressIndicator(
        value: 0.65,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        valueColor:
            const AlwaysStoppedAnimation<Color>(Colors.white),
        minHeight: 3,
      ),
    );
  }

  void _showCommentsSheet(BuildContext context, _MockReel reel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: SeeUColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: SeeUColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '\u041A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0438',
              style: SeeUTypography.title,
            ),
            const SizedBox(height: 8),
            Text(
              '${reel.commentCount} \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0435\u0432',
              style: SeeUTypography.caption.copyWith(
                color: SeeUColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: min(reel.commentCount, 10),
                itemBuilder: (_, index) {
                  final authors = _reelAuthors;
                  final author = authors[index % authors.length];
                  final comments = [
                    '\u041A\u0440\u0443\u0442\u043E!',
                    '\u041E\u0431\u0430\u043B\u0434\u0435\u0442\u044C \uD83D\uDD25',
                    '\u041A\u0430\u043A \u043A\u0440\u0430\u0441\u0438\u0432\u043E!',
                    '\u0425\u043E\u0447\u0443 \u0442\u0430\u043A\u043E\u0435 \u0436\u0435!',
                    '\u041B\u0443\u0447\u0448\u0435\u0435 \u0432\u0438\u0434\u0435\u043E \u0434\u043D\u044F',
                    '\u041F\u043E\u0434\u043F\u0438\u0441\u0430\u043B\u0441\u044F!',
                    '\u041A\u043B\u0430\u0441\u0441\u043D\u044B\u0439 \u043A\u043E\u043D\u0442\u0435\u043D\u0442 \u2764\uFE0F',
                    '\u0412\u0434\u043E\u0445\u043D\u043E\u0432\u043B\u044F\u0435\u0442!',
                    '\u041F\u0440\u043E\u0434\u043E\u043B\u0436\u0430\u0439 \u0432 \u0442\u043E\u043C \u0436\u0435 \u0434\u0443\u0445\u0435!',
                    '\u0421\u043E\u0445\u0440\u0430\u043D\u044E \u0441\u0435\u0431\u0435!',
                  ];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: author.avatarUrl != null
                              ? CachedNetworkImageProvider(author.avatarUrl!)
                              : null,
                          backgroundColor: SeeUColors.borderSubtle,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                author.username,
                                style: SeeUTypography.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: SeeUColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                comments[index % comments.length],
                                style: SeeUTypography.body.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          PhosphorIcons.heart(),
                          size: 16,
                          color: SeeUColors.textTertiary,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Comment input
            Container(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: SeeUColors.surface,
                border: Border(
                  top: BorderSide(color: SeeUColors.borderSubtle, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: SeeUColors.background,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '\u041D\u0430\u043F\u0438\u0448\u0438\u0442\u0435 \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0439...',
                        style: SeeUTypography.body.copyWith(
                          color: SeeUColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: SeeUColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: SeeUColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('\u041F\u043E\u0434\u0435\u043B\u0438\u0442\u044C\u0441\u044F', style: SeeUTypography.title),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShareOption(
                  icon: PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.fill),
                  label: '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435',
                  color: SeeUColors.accent,
                ),
                _ShareOption(
                  icon: PhosphorIcons.link(PhosphorIconsStyle.bold),
                  label: '\u0421\u0441\u044B\u043B\u043A\u0430',
                  color: const Color(0xFF546E7A),
                ),
                _ShareOption(
                  icon: PhosphorIcons.copySimple(PhosphorIconsStyle.bold),
                  label: '\u041A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C',
                  color: const Color(0xFF7C4DFF),
                ),
                _ShareOption(
                  icon: PhosphorIcons.dotsThree(PhosphorIconsStyle.bold),
                  label: '\u0415\u0449\u0451',
                  color: SeeUColors.textSecondary,
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Reel action button
// ===========================================================================

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ReelActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: color,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: SeeUTypography.micro.copyWith(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Share option button
// ===========================================================================

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: SeeUTypography.micro.copyWith(
            color: SeeUColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// User search result card
// ===========================================================================

class _UserSearchCard extends StatelessWidget {
  final dynamic user;

  const _UserSearchCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: () => context.push('/profile/${user.username}'),
      scaleFactor: 0.97,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: SeeUShadows.sm,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              backgroundColor:
                  SeeUColors.textTertiary.withValues(alpha: 0.3),
              child: user.avatarUrl == null
                  ? Text(
                      user.username[0].toUpperCase(),
                      style:
                          SeeUTypography.title.copyWith(color: Colors.white),
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
                          style: SeeUTypography.subtitle
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                            PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            color: SeeUColors.accent,
                            size: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.fullName,
                    style: SeeUTypography.caption
                        .copyWith(color: SeeUColors.textSecondary),
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
