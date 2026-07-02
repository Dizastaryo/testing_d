import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/api/api_client.dart' show networkOnlineProvider;
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/reading_provider.dart';
import '../../core/utils/format.dart';
import 'collections_screen.dart';
import 'file_preparation_screen.dart';
import 'my_uploads_screen.dart';
import 'reading_list_screen.dart';
import 'readers/open_reader.dart';
import 'package:share_plus/share_plus.dart';
import 'author_screen.dart';
import 'collection_add_sheet.dart';
import 'upload_sheet.dart';
import 'widgets/file_cover_widget.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _categoryId = '';
  String _sort = 'date';
  String _format = '';
  String _language = '';
  String _q = '';
  bool _searchOpen = false;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  final _scrollCtrl = ScrollController();

  LibraryListParams get _params =>
      LibraryListParams(categoryId: _categoryId, q: _q, sort: _sort, format: _format, language: _language);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      final st = ref.read(libraryListProvider(_params));
      // Stop auto-paging after a pagination failure (avoids tight error loop).
      if (st.pagingError || !st.hasMore || st.isLoadingMore) return;
      ref.read(libraryListProvider(_params).notifier).load();
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        final trimmed = v.trim();
        setState(() => _q = trimmed);
        if (trimmed.length >= 2) {
          ref.read(searchHistoryProvider.notifier).add(trimmed);
        }
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _debounce?.cancel();
        _searchCtrl.clear();
        _q = '';
      } else {
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocus.requestFocus();
        });
      }
    });
  }

  void _setCategory(String id) {
    HapticFeedback.selectionClick();
    setState(() => _categoryId = id);
  }

  void _setSort(String sort) {
    HapticFeedback.selectionClick();
    setState(() => _sort = sort);
  }

  void _setFormat(String format) {
    HapticFeedback.selectionClick();
    setState(() => _format = _format == format ? '' : format);
  }

  void _setLanguage(String lang) {
    HapticFeedback.selectionClick();
    setState(() => _language = _language == lang ? '' : lang);
  }

  Future<void> _openUpload() async {
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UploadSheet(),
    );
    if (result == null || result['uploaded'] != true) return;

    ref.read(libraryListProvider(_params).notifier).load(reset: true);

    if (!mounted) return;
    final title = result['title'] as String? ?? 'Файл';
    final needsPrep = result['needsPrep'] == true;

    if (needsPrep) {
      showSeeUSnackBar(
        context,
        '$title загружен — подготавливается к чтению',
        tone: SeeUTone.success,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Следить',
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const FilePreparationScreen(),
            ));
          },
        ),
      );
    } else {
      showSeeUSnackBar(context, '$title загружен', tone: SeeUTone.success);
    }
  }

  void _showMoreMenu() {
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuTile(
                icon: PhosphorIconsRegular.bookOpen,
                label: 'Моя полка',
                subtitle: 'Читаю, хочу прочитать, прочитано',
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ReadingListScreen(),
                  ));
                },
              ),
              _MenuTile(
                icon: PhosphorIconsRegular.bookBookmark,
                label: 'Коллекции',
                subtitle: 'Группируй файлы по темам',
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CollectionsScreen(),
                  ));
                },
              ),
              _MenuTile(
                icon: PhosphorIconsRegular.uploadSimple,
                label: 'Мои загрузки',
                subtitle: 'Загруженные тобой файлы',
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MyUploadsScreen(),
                  ));
                },
              ),
              _MenuTile(
                icon: PhosphorIconsRegular.cloudArrowDown,
                label: 'Скачанные',
                subtitle: 'Доступны без интернета',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/library/offline');
                },
              ),
              _MenuTile(
                icon: PhosphorIconsRegular.hourglassMedium,
                label: 'Подготовка файлов',
                subtitle: 'Статус конвертации документов',
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FilePreparationScreen(),
                  ));
                },
              ),
              _MenuTile(
                icon: PhosphorIconsRegular.trophy,
                label: 'Топ читателей',
                subtitle: 'Кто читает больше всех',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/reading/leaderboard');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listState = ref.watch(libraryListProvider(_params));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(trendingFilesProvider);
          ref.invalidate(fileCategoriesProvider);
          ref.invalidate(readingStatsProvider);
          ref.invalidate(readingListProvider('reading'));
          ref.invalidate(recentlyReadProvider);
          ref.invalidate(recentlyViewedProvider);
          ref.invalidate(readingGoalProvider);
          ref.invalidate(popularAuthorsProvider);
          ref.invalidate(recommendationsProvider);
          ref.invalidate(socialPicksProvider);
          await ref.read(libraryListProvider(_params).notifier).load(reset: true);
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            // Offline banner
            if (!ref.watch(networkOnlineProvider))
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: SeeUColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SeeUColors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsRegular.wifiSlash,
                          color: SeeUColors.amber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Офлайн-режим — показаны кэшированные данные',
                          style: TextStyle(
                              fontSize: 12,
                              color: SeeUColors.amber,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Header
            SliverToBoxAdapter(child: _buildHeader(theme)),

            // Search bar (animated)
            SliverToBoxAdapter(child: _buildSearchBar(theme)),

            // Reading stats card
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildReadingStats(theme)),

            // "Категории" — витрина категорий медиатеки (главный путь browse)
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildCategoryGrid(theme)),

            // "Продолжить чтение" — карусель книг в статусе "читаю"
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildContinueReadingRow(theme)),

            // "Читают друзья" — файлы популярные у подписок
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildSocialPicksRow(theme)),

            // "Недавно читал" — файлы по reading_progress
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildRecentlyReadRow(theme)),

            // "Недавно просматривал" — история просмотра файлов
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildRecentlyViewedRow()),

            // Trending row (hidden during search)
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildTrendingRow(theme)),

            // Recommendations (hidden during search)
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildRecommendationsRow(theme)),

            // Popular authors (hidden during search)
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildPopularAuthorsRow(theme)),

            // Sort + Category combined row
            SliverToBoxAdapter(child: _buildFilters(theme)),

            // Search results count
            if (_q.isNotEmpty && !listState.isLoading && listState.items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Найдено: ${listState.items.length}${listState.hasMore ? '+' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.seeuColors.ink3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            // File list
            if (listState.isLoading)
              _buildShimmerList(theme)
            else if (listState.items.isEmpty && !listState.isLoadingMore)
              SliverFillRemaining(
                // Branch on a load failure FIRST — иначе ошибка сети рендерилась
                // как «Библиотека пуста / Загрузи первый файл» без возможности
                // повторить. При ошибке показываем retry-состояние.
                child: listState.error != null
                    ? _buildListError(theme)
                    : _buildEmptyState(theme),
              )
            else
              _buildFileList(listState, theme),

            // Load-more indicator
            if (listState.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
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
                      style:
                          TextButton.styleFrom(foregroundColor: SeeUColors.accent),
                      icon: const Icon(PhosphorIconsRegular.arrowClockwise,
                          size: 16),
                      label: const Text('Не удалось загрузить · Повторить'),
                    ),
                  ),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final c = context.seeuColors;
    return Padding(
      padding:
          EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title block
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'БИБЛИОТЕКА',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    letterSpacing: 2.5,
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Файлы',
                  style: SeeUTypography.displayL.copyWith(
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
          // Primary actions — clean, spaced
          _HeaderButton(
            icon: _searchOpen
                ? PhosphorIconsBold.x
                : PhosphorIconsBold.magnifyingGlass,
            onTap: _toggleSearch,
            isActive: _searchOpen,
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            icon: PhosphorIconsBold.plus,
            onTap: _openUpload,
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            icon: PhosphorIconsBold.dotsThreeVertical,
            onTap: _showMoreMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final c = context.seeuColors;
    final history = ref.watch(searchHistoryProvider);

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      crossFadeState:
          _searchOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Название, автор, тема...',
                  hintStyle: TextStyle(color: c.ink4, fontSize: 14),
                  prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass,
                      size: 20, color: c.ink3),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(PhosphorIconsRegular.x,
                              size: 16, color: c.ink3),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          // Live search suggestions (shown when typing ≥2 chars)
          if (_q.length >= 2) _SearchSuggestionsPanel(query: _q, onTap: (text) {
            _searchCtrl.text = text;
            _searchCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: text.length));
            setState(() => _q = text);
            ref.read(searchHistoryProvider.notifier).add(text);
          }),

          // Search history (show when search is open but query is empty)
          if (_q.isEmpty && history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.clockCounterClockwise,
                          size: 14, color: c.ink4),
                      const SizedBox(width: 6),
                      Text('Недавние',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.ink3,
                            fontWeight: FontWeight.w600,
                          )),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => ref.read(searchHistoryProvider.notifier).clear(),
                        child: Text('Очистить',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.ink4,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: history.map((q) => GestureDetector(
                      onTap: () {
                        _searchCtrl.text = q;
                        _searchCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: q.length));
                        setState(() => _q = q);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(q,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.ink2,
                                )),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => ref
                                  .read(searchHistoryProvider.notifier)
                                  .remove(q),
                              child: Icon(PhosphorIconsRegular.x,
                                  size: 12, color: c.ink4),
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
      secondChild: const SizedBox(width: double.infinity),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Column(
      children: [
        // Sort chips
        if (_q.isEmpty) _buildSortChips(theme),
        // Format & language filter chips
        if (_q.isEmpty) _buildFormatChips(theme),
        if (_q.isEmpty) _buildLanguageChips(theme),
        // Category chips
        _buildCategoryChips(theme),
        // Active filters summary + clear
        if (_hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.funnel,
                    size: 13, color: SeeUColors.accent),
                const SizedBox(width: 6),
                Text(
                  'Фильтры активны',
                  style: TextStyle(
                    fontSize: 11,
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearAllFilters,
                  child: Text(
                    'Сбросить',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.seeuColors.ink3,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildSortChips(ThemeData theme) {
    final c = context.seeuColors;
    final sorts = [
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
                color: active ? SeeUColors.accent : Colors.transparent,
                border: Border.all(
                  color: active ? SeeUColors.accent : c.line,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 14,
                      color: active ? Colors.white : c.ink3),
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

  Widget _buildFormatChips(ThemeData theme) {
    final c = context.seeuColors;
    final formats = [
      ('pdf', 'PDF'),
      ('epub', 'EPUB'),
      ('fb2', 'FB2'),
      ('docx', 'DOCX'),
      ('txt', 'TXT'),
      ('md', 'MD'),
      ('pptx', 'PPTX'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: formats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final (key, label) = formats[i];
            final active = _format == key;
            return GestureDetector(
              onTap: () => _setFormat(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? SeeUColors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: active ? SeeUColors.accent : c.line,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? SeeUColors.accent : c.ink3,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLanguageChips(ThemeData theme) {
    final c = context.seeuColors;
    final langs = [
      ('ru', '🇷🇺 RU'),
      ('en', '🇬🇧 EN'),
      ('kk', '🇰🇿 KZ'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: langs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final (key, label) = langs[i];
            final active = _language == key;
            return GestureDetector(
              onTap: () => _setLanguage(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? SeeUColors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: active ? SeeUColors.accent : c.line,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? SeeUColors.accent : c.ink3,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openCategory(FileCategory cat) {
    HapticFeedback.selectionClick();
    context.push('/library/category/${cat.slug}', extra: cat);
  }

  /// Витрина категорий — тёплые, узнаваемые карточки. Главный путь browse.
  Widget _buildCategoryGrid(ThemeData theme) {
    final c = context.seeuColors;
    final catsAsync = ref.watch(fileCategoriesProvider);
    return catsAsync.when(
      data: (cats) {
        if (cats.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Icon(PhosphorIconsFill.compass,
                        size: 18, color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Категории',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    // Responsive column count: 2 on phones, more on wide screens.
                    final w = constraints.maxWidth;
                    final cols = w >= 720 ? 4 : (w >= 520 ? 3 : 2);
                    final cardWidth =
                        (w - spacing * (cols - 1)) / cols;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final cat in cats)
                          SizedBox(
                            width: cardWidth,
                            // Fixed height equalizes rows (names span 1–2 lines).
                            height: 148,
                            child: _CategoryGridCard(
                              category: cat,
                              countLabel: cat.filesCount > 0
                                  ? '${cat.filesCount} ${pluralMaterials(cat.filesCount)}'
                                  : 'Скоро',
                              onTap: () => _openCategory(cat),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => _buildCategoryGridError(c),
    );
  }

  /// Browse-blocking failure of the categories endpoint — show a small,
  /// retryable error instead of silently collapsing the section.
  Widget _buildCategoryGridError(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          Icon(PhosphorIconsRegular.cloudWarning, size: 40, color: c.ink3),
          const SizedBox(height: 12),
          Text(
            'Не удалось загрузить категории',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: c.ink2),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => ref.invalidate(fileCategoriesProvider),
            style: TextButton.styleFrom(foregroundColor: SeeUColors.accent),
            icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 16),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(ThemeData theme) {
    final c = context.seeuColors;
    final catsAsync = ref.watch(fileCategoriesProvider);
    return catsAsync.when(
      data: (cats) {
        final all = [FileCategory(id: '', name: 'Все'), ...cats];
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = all[i];
                final active = cat.id == _categoryId;
                return GestureDetector(
                  onTap: () => _setCategory(cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color:
                          active ? c.ink : Colors.transparent,
                      border: Border.all(
                        color: active ? c.ink : c.line,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? c.bg : c.ink2,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 46),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildTrendingRow(ThemeData theme) {
    final async = ref.watch(trendingFilesProvider);
    return async.when(
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [SeeUColors.accent, SeeUColors.accentSecondary],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.fire,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Популярное',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _TrendingCard(file: files[i]),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 80),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecommendationsRow(ThemeData theme) {
    final async = ref.watch(recommendationsProvider);
    return async.when(
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SeeUColors.plum.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.sparkle,
                              size: 14, color: SeeUColors.plum),
                          SizedBox(width: 4),
                          Text(
                            'Рекомендации',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: SeeUColors.plum,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _TrendingCard(file: files[i]),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPopularAuthorsRow(ThemeData theme) {
    final async = ref.watch(popularAuthorsProvider);
    return async.when(
      data: (authors) {
        if (authors.isEmpty) return const SizedBox.shrink();
        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Популярные авторы',
                    style: SeeUTypography.displayXS
                        .copyWith(fontWeight: FontWeight.w500, color: c.ink)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: authors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final a = authors[i];
                    final name = a['author_name'] as String? ?? '';
                    final filesCount = a['files_count'] as int? ?? 0;
                    final totalLikes = a['total_likes'] as int? ?? 0;
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AuthorScreen(authorName: name),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.line.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIconsRegular.books,
                                    size: 12, color: c.ink4),
                                const SizedBox(width: 4),
                                Text('$filesCount',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.ink3,
                                      fontFamily: 'JetBrains Mono',
                                    )),
                                const SizedBox(width: 10),
                                Icon(PhosphorIconsFill.heart,
                                    size: 12, color: SeeUColors.like),
                                const SizedBox(width: 4),
                                Text('$totalLikes',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.ink3,
                                      fontFamily: 'JetBrains Mono',
                                    )),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  bool get _hasActiveFilters =>
      _format.isNotEmpty || _language.isNotEmpty || _categoryId.isNotEmpty;

  void _clearAllFilters() {
    HapticFeedback.selectionClick();
    _debounce?.cancel();
    setState(() {
      _format = '';
      _language = '';
      _categoryId = '';
      _q = '';
      _searchCtrl.clear();
      if (_searchOpen) _searchOpen = false;
    });
  }

  /// Shown when the initial list load fails (instead of the "пусто" state),
  /// with a Повторить retry that reloads the list.
  Widget _buildListError(ThemeData theme) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.cloudWarning, size: 52, color: c.ink3),
            const SizedBox(height: 16),
            Text(
              'Не удалось загрузить',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref
                  .read(libraryListProvider(_params).notifier)
                  .load(reset: true),
              style: TextButton.styleFrom(foregroundColor: SeeUColors.accent),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final c = context.seeuColors;
    if (_q.isNotEmpty || _hasActiveFilters) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.magnifyingGlass,
                  size: 56, color: c.ink4),
              const SizedBox(height: 20),
              Text('Ничего не найдено',
                  style: SeeUTypography.displayXS.copyWith(color: c.ink2)),
              const SizedBox(height: 8),
              Text(
                _q.isNotEmpty
                    ? 'Попробуй другой запрос'
                    : 'Попробуй убрать фильтры',
                style: TextStyle(fontSize: 14, color: c.ink3),
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.x,
                            size: 14, color: SeeUColors.accent),
                        const SizedBox(width: 6),
                        Text('Сбросить фильтры',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: SeeUColors.accent,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(PhosphorIconsRegular.books,
                  size: 40, color: SeeUColors.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Библиотека пуста',
              style: SeeUTypography.displayS.copyWith(color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Загрузи первый файл и он появится здесь',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.ink3),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _openUpload,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.plus,
                        size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Загрузить файл',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingStats(ThemeData theme) {
    final async = ref.watch(readingStatsProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stats) {
        final reading = stats['books_reading'] as int? ?? 0;
        final done = stats['books_done'] as int? ?? 0;
        final want = stats['books_want'] as int? ?? 0;
        final bookmarks = stats['total_bookmarks'] as int? ?? 0;
        final streak = stats['reading_streak'] as int? ?? 0;
        if (reading + done + want + bookmarks == 0) return const SizedBox.shrink();

        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReadingListScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SeeUColors.accent.withValues(alpha: 0.08),
                    SeeUColors.accent.withValues(alpha: 0.03),
                  ],
                ),
                border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatItem(
                        value: reading,
                        label: 'Читаю',
                        color: SeeUColors.accent,
                      ),
                      _statDivider(c),
                      _StatItem(
                        value: done,
                        label: 'Прочитано',
                        color: SeeUColors.success,
                      ),
                      _statDivider(c),
                      _StatItem(
                        value: want,
                        label: 'Хочу',
                        color: const Color(0xFF1E88E5),
                      ),
                      _statDivider(c),
                      _StatItem(
                        value: bookmarks,
                        label: 'Закладки',
                        color: SeeUColors.amber,
                      ),
                    ],
                  ),
                  if (streak > 0) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: c.line.withValues(alpha: 0.3)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(PhosphorIconsFill.flame,
                            size: 14, color: SeeUColors.amber),
                        const SizedBox(width: 6),
                        Text(
                          '$streak ${_pluralDays(streak)} подряд',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SeeUColors.amber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '— серия чтения',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                    ),
                  ],
                  // Reading goal progress
                  _buildGoalRow(c, done),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGoalRow(SeeUThemeColors c, int done) {
    final goalAsync = ref.watch(readingGoalProvider);
    final goal = goalAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Divider(height: 1, color: c.line.withValues(alpha: 0.3)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _showGoalDialog(goal?.goalBooks ?? 0, done),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.target, size: 14, color: c.ink3),
              const SizedBox(width: 6),
              if (goal == null)
                Text('Поставить цель на год →',
                    style: TextStyle(fontSize: 12, color: c.ink3))
              else ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${goal.doneBooks} / ${goal.goalBooks}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: goal.achieved
                                  ? SeeUColors.success
                                  : c.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            goal.achieved
                                ? 'Цель достигнута! 🎉'
                                : 'книг в ${goal.year}',
                            style: TextStyle(fontSize: 12, color: c.ink3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: goal.progress,
                          minHeight: 4,
                          backgroundColor:
                              SeeUColors.accent.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            goal.achieved
                                ? SeeUColors.success
                                : SeeUColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(PhosphorIconsRegular.pencilSimple,
                    size: 14, color: c.ink4),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showGoalDialog(int current, int done) async {
    final ctrl = TextEditingController(
        text: current > 0 ? '$current' : '');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Цель чтения на год', style: SeeUTypography.displayS),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Уже прочитано: $done книг',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Сколько книг хочешь прочитать?',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          if (current > 0)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(-1),
              child: const Text('Удалить', style: TextStyle(color: SeeUColors.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Сохранить',
                style: TextStyle(color: SeeUColors.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || result == null) return;
    final dio = ref.read(libraryApiClientProvider);
    if (result == -1) {
      await dio.delete(ApiEndpoints.myReadingGoal,
          queryParameters: {'year': DateTime.now().year});
    } else if (result > 0) {
      await dio.put(ApiEndpoints.myReadingGoal,
          data: {'goal_books': result},
          queryParameters: {'year': DateTime.now().year});
    }
    ref.invalidate(readingGoalProvider);
  }

  String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'дня';
    }
    return 'дней';
  }

  Widget _statDivider(SeeUThemeColors c) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: c.line.withValues(alpha: 0.4),
    );
  }

  Widget _buildContinueReadingRow(ThemeData theme) {
    final async = ref.watch(readingListProvider('reading'));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(PhosphorIconsFill.bookOpen,
                        size: 16, color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Продолжить чтение',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w500, color: c.ink),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ReadingListScreen()),
                      ),
                      child: Text(
                        'Все',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SeeUColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 188,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _ContinueReadingCard(file: files[i]),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSocialPicksRow(ThemeData theme) {
    final async = ref.watch(socialPicksProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(PhosphorIconsFill.usersThree,
                        size: 16, color: const Color(0xFF1E88E5)),
                    const SizedBox(width: 8),
                    Text(
                      'Читают друзья',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 188,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ContinueReadingCard(file: files[i]),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentlyReadRow(ThemeData theme) {
    final async = ref.watch(recentlyReadProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        // Don't show if empty, or if same as continue reading
        if (files.isEmpty) return const SizedBox.shrink();
        // Filter out files already in "reading" status to avoid duplicates
        final readingFiles = ref.watch(readingListProvider('reading')).valueOrNull ?? [];
        final readingIds = readingFiles.map((f) => f.id).toSet();
        final filtered = files.where((f) => !readingIds.contains(f.id)).toList();
        if (filtered.isEmpty) return const SizedBox.shrink();

        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.clockCounterClockwise,
                        size: 16, color: c.ink3),
                    const SizedBox(width: 8),
                    Text(
                      'Недавно читал',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 188,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _ContinueReadingCard(file: filtered[i]),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentlyViewedRow() {
    final async = ref.watch(recentlyViewedProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        // Filter out files the user is actively reading (avoid duplicate rows)
        final readingFiles = ref.watch(readingListProvider('reading')).valueOrNull ?? [];
        final readingIds = readingFiles.map((f) => f.id).toSet();
        final filtered = files.where((f) => !readingIds.contains(f.id)).take(15).toList();
        if (filtered.isEmpty) return const SizedBox.shrink();

        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.eye, size: 16, color: c.ink3),
                    const SizedBox(width: 8),
                    Text(
                      'Просматривал',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final f = filtered[i];
                    return GestureDetector(
                      onTap: () => ctx.push('/files/${f.id}'),
                      child: SizedBox(
                        width: 88,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FileCoverWidget(
                                file: f,
                                width: 88,
                                height: 116,
                                borderRadius: 8,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              f.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: c.ink2,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerList(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E8E8);
    final highlight = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return SliverToBoxAdapter(
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
                6,
                (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    )),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(LibraryListState state, ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FileCard(file: state.items[i]),
          ),
          childCount: state.items.length,
        ),
      ),
    );
  }
}

// ─── Category Grid Card ────────────────────────────────────────────────────

class _CategoryGridCard extends StatelessWidget {
  final FileCategory category;
  final String countLabel;
  final VoidCallback onTap;

  const _CategoryGridCard({
    required this.category,
    required this.countLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final accent = category.colorValue;
    final empty = category.filesCount == 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Opacity(
          opacity: empty ? 0.62 : 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: c.isDark ? 0.20 : 0.12),
                  accent.withValues(alpha: c.isDark ? 0.07 : 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(category.iconData, size: 26, color: accent),
                ),
                const SizedBox(height: 12),
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    // Darken pale category colors so the label stays readable.
                    color:
                        empty ? c.ink4 : readableInk(accent, isDark: c.isDark),
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

// ─── Header Button ─────────────────────────────────────────────────────────

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? Colors.white : c.ink2,
        ),
      ),
    );
  }
}

// ─── Menu Tile ──────────────────────────────────────────────────────────────

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SeeUColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: SeeUColors.accent),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: c.ink)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: c.ink3)),
      trailing: Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.ink4),
      onTap: onTap,
    );
  }
}

// ─── Trending Card ──────────────────────────────────────────────────────────

class _TrendingCard extends StatelessWidget {
  final FileItem file;

  const _TrendingCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            Hero(
              tag: 'file_cover_trending_${file.id}',
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: FileCoverWidget(
                  file: file,
                  width: 120,
                  height: 150,
                  borderRadius: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              file.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            // Author or stats
            if (file.authorName.isNotEmpty)
              Text(
                file.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.ink3),
              )
            else
              Row(
                children: [
                  Icon(PhosphorIconsFill.heart,
                      size: 10, color: SeeUColors.like.withValues(alpha: 0.6)),
                  const SizedBox(width: 3),
                  Text('${file.likesCount}',
                      style: TextStyle(fontSize: 10, color: c.ink3)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── File Card ──────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final FileItem file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final color = colorForFileType(file.fileExtension);

    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showFileContextMenu(context, file);
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
                offset: const Offset(0, 3))
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover — larger, with shadow
                  Hero(
                    tag: 'file_cover_${file.id}',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: FileCoverWidget(
                          file: file, width: 56, height: 76, borderRadius: 10),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Right content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
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

                        // Format + category chips
                        Row(
                          children: [
                            _FormatBadge(
                                label: file.formatLabel, color: color),
                            if (file.category case final cat?
                                when cat.name.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Builder(
                                  builder: (_) {
                                    // Compute color once; darken pale colors so
                                    // the label stays readable on the tint.
                                    final catColor = cat.colorValue;
                                    final catInk = readableInk(catColor,
                                        isDark: c.isDark);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(cat.iconData,
                                              size: 11, color: catInk),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              cat.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: catInk,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Stats row
                        Row(
                          children: [
                            Icon(
                              file.isLiked
                                  ? PhosphorIconsFill.heart
                                  : PhosphorIconsRegular.heart,
                              size: 12,
                              color: file.isLiked
                                  ? SeeUColors.accent
                                  : SeeUColors.like.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 3),
                            Text('${file.likesCount}',
                                style: file.isLiked
                                    ? _statStyle(c).copyWith(
                                        color: SeeUColors.accent,
                                        fontWeight: FontWeight.w700)
                                    : _statStyle(c)),
                            const SizedBox(width: 12),
                            Icon(PhosphorIconsRegular.eye,
                                size: 12, color: c.ink4),
                            const SizedBox(width: 3),
                            Text(_formatCount(file.viewsCount),
                                style: _statStyle(c)),
                            const SizedBox(width: 12),
                            Icon(PhosphorIconsRegular.download,
                                size: 12, color: c.ink4),
                            const SizedBox(width: 3),
                            Text(file.downloadsFormatted,
                                style: _statStyle(c)),
                            if (file.ratingsCount > 0) ...[
                              const SizedBox(width: 12),
                              const Icon(PhosphorIconsFill.star,
                                  size: 12, color: SeeUColors.amber),
                              const SizedBox(width: 3),
                              Text(file.averageRating.toStringAsFixed(1),
                                  style: _statStyle(c)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Reading status badge (top right)
            if (file.readingStatus != null)
              Positioned(
                top: 10,
                right: 10,
                child: _readingBadge(file.readingStatus!),
              ),
          ],
        ),
      ),
    );
  }

  TextStyle _statStyle(SeeUThemeColors c) => TextStyle(
        fontSize: 11,
        color: c.ink4,
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w500,
      );

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _showFileContextMenu(BuildContext context, FileItem file) {
    final c = context.seeuColors;
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(file.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: c.ink)),
            const SizedBox(height: 16),
            _ContextMenuItem(
              icon: PhosphorIconsRegular.bookOpen,
              label: 'Открыть',
              onTap: () {
                Navigator.pop(ctx);
                context.push('/files/${file.id}');
              },
            ),
            _ContextMenuItem(
              icon: PhosphorIconsRegular.bookBookmark,
              label: 'В коллекцию',
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CollectionAddSheet(fileId: file.id),
                );
              },
            ),
            _ContextMenuItem(
              icon: PhosphorIconsRegular.shareNetwork,
              label: 'Поделиться',
              onTap: () {
                Navigator.pop(ctx);
                final info = file.authorName.isNotEmpty
                    ? '${file.displayTitle} — ${file.authorName}'
                    : file.displayTitle;
                Share.share(
                  '$info\n\nОткрыть в SeeU: seeu://files/${file.id}',
                  subject: file.displayTitle,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _readingBadge(String status) {
    Color bg;
    String label;
    switch (status) {
      case 'reading':
        bg = SeeUColors.accent;
        label = 'Читаю';
      case 'done':
        bg = SeeUColors.success;
        label = 'Прочитано';
      case 'want':
        bg = const Color(0xFF1E88E5);
        label = 'Хочу';
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Format Badge ───────────────────────────────────────────────────────────

class _FormatBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _FormatBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}

// ─── Continue Reading Card ───────────────────────────────────────────────────

class _ContinueReadingCard extends ConsumerWidget {
  final FileItem file;
  const _ContinueReadingCard({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final progressAsync = ref.watch(readingProgressProvider(file.id));
    final progress = progressAsync.valueOrNull;

    return GestureDetector(
      onTap: () {
        if (canRead(file)) {
          openReader(context, file);
        } else {
          context.push('/files/${file.id}');
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        context.push('/files/${file.id}');
      },
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 110,
                  height: 145,
                  child: Stack(
                    children: [
                      FileCoverWidget(
                          file: file, width: 110, height: 145, borderRadius: 0),
                      // % overlay at bottom
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (canRead(file))
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(PhosphorIconsFill.play,
                                        size: 10, color: Colors.white.withValues(alpha: 0.9)),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Читать',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const SizedBox.shrink(),
                              if (progress != null && progress.percentage > 0)
                                Text(
                                  '${(progress.percentage * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'JetBrains Mono',
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
            const SizedBox(height: 6),
            // Title
            Text(
              file.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: c.ink),
            ),
            const SizedBox(height: 4),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress?.percentage ?? 0,
                minHeight: 3,
                backgroundColor: SeeUColors.accent.withValues(alpha: 0.12),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(SeeUColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search Suggestions Panel ────────────────────────────────────────────────

class _SearchSuggestionsPanel extends ConsumerWidget {
  final String query;
  final void Function(String) onTap;

  const _SearchSuggestionsPanel({required this.query, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchSuggestionsProvider(query));
    final c = context.seeuColors;

    final suggestions = async.valueOrNull ?? [];
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: suggestions.take(6).toList().asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final text = s['text'] as String? ?? '';
          final type = s['type'] as String? ?? 'title';
          final isLast = i == (suggestions.length - 1) || i == 5;

          return GestureDetector(
            onTap: () => onTap(text),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                            color: c.line.withValues(alpha: 0.4))),
              ),
              child: Row(
                children: [
                  Icon(
                    type == 'author'
                        ? PhosphorIconsRegular.user
                        : PhosphorIconsRegular.file,
                    size: 14,
                    color: c.ink3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: c.ink),
                    ),
                  ),
                  Icon(PhosphorIconsRegular.arrowUpLeft,
                      size: 14, color: c.ink4),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Stat Item (for reading stats card) ──────────────────────────────────────

class _StatItem extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: context.seeuColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Context Menu Item ──────────────────────────────────────────────────────

class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ContextMenuItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.ink2),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                )),
          ],
        ),
      ),
    );
  }
}
