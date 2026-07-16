import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/analytics/interest_tracker.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../../core/models/user.dart';
import '../../core/providers/user_provider.dart';

/// §04 B: поиск — отдельный экран (вход тапом по строке на «Интересном»).
/// Бар в фокусе с коралловой обводкой + «Отмена», вкладки «Публикации» /
/// «Аккаунты» (активная — чёрная пилюля), публикации — 2 колонки.
class ExploreSearchScreen extends ConsumerStatefulWidget {
  const ExploreSearchScreen({super.key});

  @override
  ConsumerState<ExploreSearchScreen> createState() =>
      _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends ConsumerState<ExploreSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _selectedTab = 0;

  static const List<String> _tabs = ['Публикации', 'Аккаунты'];

  @override
  void initState() {
    super.initState();
    // Свежий заход в поиск — прошлые результаты не должны мигать.
    // searchProvider живёт всё время жизни приложения: его _searchType мог
    // остаться 'users' с прошлого визита, а локальный _selectedTab=0
    // (Публикации) — иначе бэкенд вернёт только users и вкладка Публикаций
    // покажет «ничего не нашлось».
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchProvider.notifier)
        ..clear()
        ..setSearchType('posts');
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // searchProvider.search() уже дебаунсит (400мс) — второй локальный таймер
    // вокруг него давал двойную задержку ~800мс. Зовём напрямую.
    ref.read(searchProvider.notifier).search(value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {});
      return;
    }
    // Аналитику шлём один раз на устоявшийся запрос, не на каждый символ.
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final q = value.trim();
      ref.read(interestTrackerProvider).track(
        eventType: 'explore_search',
        entityType: 'query',
        source: 'explore',
        metadata: {'q': q.length > 64 ? q.substring(0, 64) : q},
      );
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final searchState = ref.watch(searchProvider);
    final hasQuery = _searchCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Бар в фокусе + «Отмена» ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: SeeUColors.accent, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: SeeUColors.accent.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsRegular.magnifyingGlass,
                              size: 18, color: SeeUColors.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _focusNode,
                              onChanged: _onChanged,
                              textInputAction: TextInputAction.search,
                              style: SeeUTypography.body
                                  .copyWith(fontSize: 14, color: c.ink),
                              cursorColor: SeeUColors.accent,
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: 'Искать людей, звуки, теги',
                                hintStyle: SeeUTypography.body
                                    .copyWith(fontSize: 14, color: c.ink3),
                              ),
                            ),
                          ),
                          if (hasQuery)
                            Tappable(
                              onTap: () {
                                _searchCtrl.clear();
                                ref.read(searchProvider.notifier).clear();
                                setState(() {});
                              },
                              child: Icon(PhosphorIconsFill.xCircle,
                                  size: 18, color: c.ink4),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tappable(
                    onTap: () => context.pop(),
                    child: Text('Отмена',
                        style: SeeUTypography.caption.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: SeeUColors.accent)),
                  ),
                ],
              ),
            ),

            // ── Вкладки: Публикации | Аккаунты ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final active = _selectedTab == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tappable(
                      onTap: () {
                        setState(() => _selectedTab = i);
                        ref
                            .read(searchProvider.notifier)
                            .setSearchType(i == 0 ? 'posts' : 'users');
                      },
                      child: AnimatedContainer(
                        duration: SeeUMotion.quick,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? c.ink : c.surface,
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                          border: active ? null : Border.all(color: c.line),
                        ),
                        child: Text(_tabs[i],
                            style: SeeUTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: active ? c.bg : c.ink2)),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Результаты ──────────────────────────────────────────
            Expanded(
              child: !hasQuery
                  ? _EmptyPrompt(color: c)
                  : _buildResults(searchState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(SearchState searchState) {
    final c = context.seeuColors;
    if (searchState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    final users = _selectedTab == 1 ? searchState.users : <User>[];
    final posts = _selectedTab == 0 ? searchState.posts : <Post>[];

    if (users.isEmpty && posts.isEmpty) {
      // §04: «Ничего не нашлось» — serif-заголовок + подсказка.
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsRegular.magnifyingGlass,
                    size: 24, color: c.ink3),
              ),
              const SizedBox(height: 10),
              Text('Ничего не нашлось',
                  style: SeeUTypography.displayS
                      .copyWith(fontSize: 18, color: c.ink)),
              const SizedBox(height: 6),
              Text('Проверь запрос или поищи звук либо тег.',
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption
                      .copyWith(fontSize: 12, color: c.ink3)),
            ],
          ),
        ),
      );
    }

    if (_selectedTab == 1) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => UserSearchCard(user: users[i]),
      );
    }

    // Публикации — 2 колонки (§04 B), плитки r14.
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 150,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final imgUrl = post.gridThumbnailUrl;
        final hasVideo = post.media.any((m) => m.type == MediaType.video);
        return GestureDetector(
          onTap: () => context.push('/post/${post.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                imgUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imgUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(color: c.surface2),
                if (hasVideo)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                        PhosphorIcons.playCircle(PhosphorIconsStyle.fill),
                        color: Colors.white,
                        size: 20,
                        shadows: const [
                          Shadow(
                              color: SeeUColors.mediumScrim, blurRadius: 4),
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
                          Shadow(
                              color: SeeUColors.mediumScrim, blurRadius: 4),
                        ]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// До ввода запроса экран не пустует — короткая подсказка.
class _EmptyPrompt extends StatelessWidget {
  final SeeUThemeColors color;
  const _EmptyPrompt({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Text(
        'Ищи людей по нику или имени, публикации — по подписи.',
        style:
            SeeUTypography.caption.copyWith(fontSize: 12, color: color.ink3),
      ),
    );
  }
}

/// Карточка человека в результатах поиска.
class UserSearchCard extends StatelessWidget {
  final User user;
  const UserSearchCard({super.key, required this.user});

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
              radius: 22,
              backgroundColor: c.surface2,
              backgroundImage:
                  user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(user.avatarUrl!)
                      : null,
              child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                  ? Text(
                      user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : '?',
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
                          style: SeeUTypography.subtitle
                              .copyWith(fontWeight: FontWeight.w600),
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
