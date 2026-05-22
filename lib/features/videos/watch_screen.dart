import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/tokens.dart';
import '../../core/models/video.dart';
import '../../core/providers/video_provider.dart';

class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  String _activeCategory = '';
  String _query = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Video> _applySearch(List<Video> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((v) =>
            v.title.toLowerCase().contains(q) ||
            v.description.toLowerCase().contains(q) ||
            (v.user?.username.toLowerCase().contains(q) ?? false) ||
            (v.user?.fullName.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final categoriesAsync = ref.watch(videoCategoriesProvider);
    final featuredAsync = ref.watch(videosFeaturedProvider);
    final videosAsync = ref.watch(videosProvider(_activeCategory.isEmpty ? null : _activeCategory));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(theme)),
          if (_searchOpen) SliverToBoxAdapter(child: _buildSearchField(theme)),
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (cats) => _buildCategories(cats, theme),
              loading: () => const SizedBox(height: 50),
              error: (_, __) => const SizedBox(),
            ),
          ),
          if (_query.isEmpty)
            SliverToBoxAdapter(
              child: featuredAsync.when(
                data: (video) => video != null ? _buildFeaturedCard(video, theme, isDark) : const SizedBox(),
                loading: () => const SizedBox(height: 200),
                error: (_, __) => const SizedBox(),
              ),
            ),
          videosAsync.when(
            data: (videos) {
              final filtered = _applySearch(videos);
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Видео ещё нет'
                            : 'По запросу «$_query» ничего',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                );
              }
              return _buildGrid(filtered, theme);
            },
            loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverToBoxAdapter(child: Center(child: Text('Ошибка загрузки: $e'))),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Поиск по видео…',
          prefixIcon: Icon(PhosphorIcons.magnifyingGlass()),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '◐ CINEMA · LIVE',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Видео',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Загрузить видео',
                onPressed: () => context.push('/videos/upload'),
                icon: Icon(
                  PhosphorIcons.plusCircle(),
                  color: SeeUColors.accent,
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    _query = '';
                  }
                }),
                icon: Icon(
                  _searchOpen ? PhosphorIcons.x() : PhosphorIcons.magnifyingGlass(),
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(List<VideoCategory> cats, ThemeData theme) {
    final allCats = [VideoCategory(id: '', name: 'Все'), ...cats];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: allCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final isActive = cat.id == _activeCategory;
          return GestureDetector(
            onTap: () => setState(() => _activeCategory = cat.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? theme.colorScheme.onSurface : Colors.transparent,
                border: isActive ? null : Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? theme.scaffoldBackgroundColor : theme.colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedCard(Video video, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => context.push('/videos/${video.id}'),
        child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [SeeUColors.accent.withValues(alpha: 0.8), Colors.black87],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: SeeUColors.accent.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.3, 1.0],
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeeUColors.accent,
                  boxShadow: [BoxShadow(color: SeeUColors.accent.withValues(alpha: 0.6), blurRadius: 30)],
                ),
                child: Icon(PhosphorIcons.play(PhosphorIconsStyle.fill), color: Colors.white, size: 28),
              ),
            ),
            if (video.isLive)
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                      const SizedBox(width: 4),
                      Text('LIVE · ${video.viewsFormatted}', style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text('${video.resolution} · HDR', style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, color: Colors.white, letterSpacing: 1, fontWeight: FontWeight.w600)),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, fontWeight: FontWeight.w400, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('@${video.user?.username ?? ''} · ${video.durationFormatted} · ${video.viewsFormatted} views', style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildGrid(List<Video> videos, ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.65,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _buildVideoCard(videos[i], theme),
          childCount: videos.length,
        ),
      ),
    );
  }

  Widget _buildVideoCard(Video video, ThemeData theme) {
    return GestureDetector(
      onTap: () => context.push('/videos/${video.id}'),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [SeeUColors.accent.withValues(alpha: 0.4), Colors.black54],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                if (video.thumbnailUrl.isNotEmpty)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(video.thumbnailUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                    child: Text(video.durationFormatted, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text('@${video.user?.username ?? ''} · ${video.viewsFormatted} views', style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
      ],
      ),
    );
  }
}
