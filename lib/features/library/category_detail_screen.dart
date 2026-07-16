import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import 'library_design.dart';
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

  /// Категория: из extra или по slug из справочника. Getter вместо поля,
  /// которое раньше присваивалось прямо в build() (мутация State во время
  /// сборки — хрупко и могло рассинхрониться при повторных build).
  FileCategory? get _cat {
    final w = widget.category;
    if (w != null) return w;
    final cats = ref.read(fileCategoriesProvider).valueOrNull;
    if (cats == null) return null;
    for (final x in cats) {
      if (x.slug == widget.slug) return x;
    }
    return null;
  }

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
          label: 'В библиотеку',
          icon: PhosphorIconsRegular.books,
          onTap: () => context.go('/files'),
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
      body: PaperBackground(
        child: RefreshIndicator(
        color: accent,
        onRefresh: () async {
          await ref.read(libraryListProvider(_params).notifier).load(reset: true);
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
                child: _buildHeader(c, accent, cat, listState.items.length)),
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
              // Полка: обложки-корешки в три колонки, как книги на стеллаже.
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
                    childAspectRatio: 0.58,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _CategoryShelfItem(file: listState.items[i]),
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
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  // Полка категории: единая стрелка «Назад», крупная плашка-иконка в цвете
  // категории, серифный заголовок и строка «N материалов · сортировка».
  Widget _buildHeader(
      SeeUThemeColors c, Color accent, FileCategory cat, int loadedCount) {
    // Категория, пришедшая с чипа файла, не несёт files_count (0) — берём
    // число из полного справочника категорий, иначе шапка показывала «Пока
    // пусто» над непустой полкой.
    var count = cat.filesCount;
    if (count <= 0) {
      final full = ref
          .watch(fileCategoriesProvider)
          .valueOrNull
          ?.where((x) => x.id == cat.id || x.slug == cat.slug)
          .firstOrNull;
      if (full != null) count = full.filesCount;
    }
    // Справочник недоступен, но файлы уже загружены — честнее промолчать,
    // чем писать «Пока пусто».
    final showEmptyLabel = count <= 0 && loadedCount == 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LibBackButton(),
          const SizedBox(height: 18),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: c.isDark ? 0.2 : 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(cat.iconData, size: 32, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            cat.name,
            style: SeeUTypography.displayS.copyWith(
              fontSize: 38,
              height: 1,
              letterSpacing: -1,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          if (cat.description != null && cat.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              cat.description!,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.ink2),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (count > 0 || showEmptyLabel) ...[
                Text(
                  count > 0
                      ? '$count ${pluralMaterials(count)}'
                      : 'Пока пусто',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: LibColors.kicker(context),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.ink4,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Icon(PhosphorIcons.arrowsDownUp(), size: 13, color: c.ink3),
              const SizedBox(width: 5),
              Text(
                _sortLabel(_sort),
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _sortLabel(String sort) => switch (sort) {
        'likes' => 'Популярные',
        'views' => 'Просматриваемые',
        'rating' => 'По оценке',
        'downloads' => 'Скачиваемые',
        'title' => 'А–Я',
        _ => 'Новые',
      };

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

/// Книга на полке категории: корешок + короткое название под ним.
class _CategoryShelfItem extends StatelessWidget {
  final FileItem file;
  const _CategoryShelfItem({required this.file});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/files/${file.id}');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => BookSpine(
                file: file,
                width: box.maxWidth,
                height: box.maxHeight,
                radius: 10,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            file.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

