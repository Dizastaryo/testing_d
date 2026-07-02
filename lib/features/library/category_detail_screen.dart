import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import 'widgets/file_cover_widget.dart';
import '../../core/utils/format.dart';

/// «Полка» одной категории медиатеки: крупная обложка-заголовок с иконкой
/// категории в её фирменном цвете, описание, счётчик и бесконечная лента
/// файлов с сортировкой и pull-to-refresh.
class CategoryDetailScreen extends ConsumerStatefulWidget {
  /// Provided on in-app navigation (happy path). Null on cold-start / deep-link
  /// — the screen then resolves the category from [slug].
  final FileCategory? category;

  /// Category slug from the route (`/library/category/:slug`). Used to
  /// self-resolve via [fileCategoriesProvider] when [category] is null.
  final String slug;

  const CategoryDetailScreen({super.key, this.category, this.slug = ''});

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  String _sort = 'date';
  final _scrollCtrl = ScrollController();

  // Category resolved from [slug] when not supplied via extra.
  FileCategory? _resolvedCategory;

  FileCategory? get _cat => widget.category ?? _resolvedCategory;

  LibraryListParams get _params =>
      LibraryListParams(categoryId: _cat?.id ?? '', sort: _sort);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_cat == null) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      final st = ref.read(libraryListProvider(_params));
      // Stop auto-paging after a pagination failure (avoids tight error loop).
      if (st.pagingError || !st.hasMore || st.isLoadingMore) return;
      ref.read(libraryListProvider(_params).notifier).load();
    }
  }

  void _setSort(String sort) {
    if (_sort == sort) return;
    HapticFeedback.selectionClick();
    setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    if (cat != null) return _buildContent(cat);

    // Deep-link / cold-start: resolve the category from the slug.
    final catsAsync = ref.watch(fileCategoriesProvider);
    return catsAsync.when(
      data: (cats) {
        FileCategory? found;
        for (final x in cats) {
          if (x.slug == widget.slug) {
            found = x;
            break;
          }
        }
        if (found == null) return _buildNotFound();
        _resolvedCategory = found;
        return _buildContent(found);
      },
      loading: () => _buildResolving(),
      error: (_, __) => _buildNotFound(),
    );
  }

  // Glass-шапка для сервисных состояний (resolving / not-found).
  Widget _serviceScaffold({required Widget body}) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          body,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Библиотека',
              titleText: 'Категория',
              leading: Tappable(
                onTap: () => context.pop(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(PhosphorIconsRegular.arrowLeft,
                      size: 20, color: c.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Loader shown while categories load on a cold-start deep-link.
  Widget _buildResolving() {
    return _serviceScaffold(
      body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  // Not-found state when the slug matches no category.
  Widget _buildNotFound() {
    return _serviceScaffold(
      body: SeeUEmptyState(
        icon: PhosphorIconsRegular.folderOpen,
        title: 'Категория не найдена',
        subtitle: 'Возможно, она была удалена или переименована',
        action: SeeUStateAction(
          label: 'В медиатеку',
          icon: PhosphorIconsRegular.books,
          onTap: () => context.go('/library'),
        ),
      ),
    );
  }

  Widget _buildContent(FileCategory cat) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final accent = cat.colorValue;
    final listState = ref.watch(libraryListProvider(_params));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: accent,
        onRefresh: () async {
          await ref.read(libraryListProvider(_params).notifier).load(reset: true);
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(c, accent, cat)),
            SliverToBoxAdapter(child: _buildSortChips(c, accent)),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            if (listState.isLoading)
              _buildShimmer(c)
            else if (listState.items.isEmpty && !listState.isLoadingMore)
              SliverFillRemaining(
                hasScrollBody: false,
                child: listState.error != null
                    ? _buildError(c, accent)
                    : _buildEmpty(c, accent, cat),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CategoryFileCard(
                          file: listState.items[i], accent: accent),
                    ),
                    childCount: listState.items.length,
                  ),
                ),
              ),

            if (listState.isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: accent),
                    ),
                  ),
                ),
              )
            else if (listState.pagingError && listState.items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () => ref
                          .read(libraryListProvider(_params).notifier)
                          .retryLoadMore(),
                      style: TextButton.styleFrom(foregroundColor: accent),
                      icon: const Icon(PhosphorIconsRegular.arrowClockwise,
                          size: 16),
                      label: const Text('Не удалось загрузить · Повторить'),
                    ),
                  ),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader(SeeUThemeColors c, Color accent, FileCategory cat) {
    final count = cat.filesCount;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 8, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: c.isDark ? 0.22 : 0.14),
            accent.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          Row(
            children: [
              SeeUGlassCircleButton(
                icon: Icon(PhosphorIconsBold.arrowLeft, size: 18, color: c.ink),
                tint: accent,
                onTap: () => context.pop(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Big icon badge in category color
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.95),
                  accent.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(cat.iconData, size: 38, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            'КАТЕГОРИЯ',
            style: SeeUTypography.kicker.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 4),
          Text(
            cat.name,
            style: SeeUTypography.displayL.copyWith(color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            count > 0
                ? '$count ${pluralMaterials(count)}'
                : 'Пока пусто',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          if (cat.description != null && cat.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              cat.description!,
              style: TextStyle(fontSize: 14, height: 1.45, color: c.ink2),
            ),
          ],
        ],
      ),
    );
  }

  // ── Sort chips ──────────────────────────────────────────────────────────
  Widget _buildSortChips(SeeUThemeColors c, Color accent) {
    const sorts = [
      ('date', 'Новые', PhosphorIconsRegular.clock),
      ('likes', 'Популярные', PhosphorIconsRegular.heart),
      ('views', 'Просматриваемые', PhosphorIconsRegular.eye),
      ('rating', 'По оценке', PhosphorIconsRegular.star),
      ('downloads', 'Скачиваемые', PhosphorIconsRegular.download),
      ('title', 'А–Я', PhosphorIconsRegular.textAa),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sorts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, label, icon) = sorts[i];
          final active = _sort == key;
          return GestureDetector(
            onTap: () => _setSort(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? accent : Colors.transparent,
                border: Border.all(color: active ? accent : c.line),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: active ? Colors.white : c.ink3),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : c.ink2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── States ──────────────────────────────────────────────────────────────
  Widget _buildShimmer(SeeUThemeColors c) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer.fromColors(
              baseColor: c.surface2,
              highlightColor: c.surface,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          childCount: 6,
        ),
      ),
    );
  }

  Widget _buildEmpty(SeeUThemeColors c, Color accent, FileCategory cat) {
    return SeeUEmptyState(
      icon: cat.iconData,
      title: 'В этой категории пока пусто',
      subtitle: 'Скоро здесь появятся материалы — загляните позже',
    );
  }

  Widget _buildError(SeeUThemeColors c, Color accent) {
    return SeeUErrorState(
      icon: PhosphorIconsRegular.cloudWarning,
      onRetry: () =>
          ref.read(libraryListProvider(_params).notifier).load(reset: true),
    );
  }
}

// ─── Compact file card (category color accent) ──────────────────────────────
class _CategoryFileCard extends StatelessWidget {
  final FileItem file;
  final Color accent;
  const _CategoryFileCard({required this.file, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/files/${file.id}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: c.line.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'file_cover_${file.id}',
                child: FileCoverWidget(
                    file: file, width: 54, height: 74, borderRadius: 10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.3),
                    ),
                    if (file.authorName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        file.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.ink3),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorForFileType(file.fileExtension)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            file.formatLabel,
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colorForFileType(file.fileExtension),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          file.isLiked
                              ? PhosphorIconsFill.heart
                              : PhosphorIconsRegular.heart,
                          size: 13,
                          color: file.isLiked ? SeeUColors.like : c.ink4,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${file.likesCount}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: c.ink3,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        Icon(PhosphorIconsRegular.eye, size: 13, color: c.ink4),
                        const SizedBox(width: 4),
                        Text(
                          '${file.viewsCount}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: c.ink3,
                              fontWeight: FontWeight.w500),
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
    );
  }
}
