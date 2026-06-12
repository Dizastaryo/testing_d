import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
import 'upload_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _categoryId = '';
  String _sort = 'date';
  String _q = '';
  bool _searchOpen = false;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  final _scrollCtrl = ScrollController();

  LibraryListParams get _params =>
      LibraryListParams(categoryId: _categoryId, q: _q, sort: _sort);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(libraryListProvider(_params).notifier).load();
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  void _setCategory(String id) => setState(() => _categoryId = id);
  void _setSort(String sort) => setState(() => _sort = sort);

  Future<void> _openUpload() async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UploadSheet(),
    );
    if (uploaded == true) {
      ref.read(libraryListProvider(_params).notifier).load(reset: true);
    }
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
          ref.read(libraryListProvider(_params).notifier).load(reset: true);
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            // Header
            SliverToBoxAdapter(child: _buildHeader(theme)),

            // Search bar (collapsible)
            if (_searchOpen)
              SliverToBoxAdapter(child: _buildSearchBar(theme)),

            // Trending row (hidden during search)
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildTrendingRow(theme)),

            // Sort chips
            if (_q.isEmpty)
              SliverToBoxAdapter(child: _buildSortChips(theme)),

            // Category chips
            SliverToBoxAdapter(child: _buildCategoryChips(theme)),

            // File list
            if (listState.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (listState.items.isEmpty && !listState.isLoadingMore)
              SliverFillRemaining(
                child: _buildEmptyState(theme),
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
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 12, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '▮ БИБЛИОТЕКА',
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
                'Файлы',
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
          const Spacer(),
          IconButton(
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchCtrl.clear();
                  _q = '';
                }
              });
            },
            icon: Icon(
              _searchOpen ? PhosphorIconsRegular.x : PhosphorIconsRegular.magnifyingGlass,
              color: theme.colorScheme.onSurface,
            ),
          ),
          IconButton(
            onPressed: _openUpload,
            icon: Icon(PhosphorIconsBold.plus, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Поиск по названию, автору…',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildSortChips(ThemeData theme) {
    final sorts = [
      ('date', 'Новые'),
      ('likes', 'По лайкам'),
      ('downloads', 'По скачиваниям'),
      ('title', 'А-Я'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sorts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (key, label) = sorts[i];
          final active = _sort == key;
          return GestureDetector(
            onTap: () => _setSort(key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? SeeUColors.accent : Colors.transparent,
                border: Border.all(
                  color: active ? SeeUColors.accent : theme.dividerColor,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips(ThemeData theme) {
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? theme.colorScheme.onSurface : Colors.transparent,
                      border: Border.all(
                        color: active ? theme.colorScheme.onSurface : theme.dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? theme.scaffoldBackgroundColor
                            : theme.colorScheme.onSurface,
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text('Популярное',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      )),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _buildTrendingCard(files[i], theme),
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

  Widget _buildTrendingCard(FileItem file, ThemeData theme) {
    final color = colorForFileType(file.fileExtension);
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    file.formatLabel,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (file.authorName.isNotEmpty)
              Text(
                file.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            const Spacer(),
            Row(
              children: [
                Icon(PhosphorIconsFill.heart, size: 11,
                    color: SeeUColors.like.withValues(alpha: 0.7)),
                const SizedBox(width: 3),
                Text('${file.likesCount}',
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(width: 8),
                Icon(PhosphorIconsRegular.download, size: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 3),
                Text(file.downloadsFormatted,
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    if (_q.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.magnifyingGlass,
                  size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
              const SizedBox(height: 16),
              Text('По запросу «$_q» ничего не найдено',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
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
            Icon(PhosphorIconsRegular.books,
                size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Здесь пока ничего нет.\nЗагрузи первую книгу!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _openUpload,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('+ Загрузить',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
            ),
          ],
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

// ─── File Card ──────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final FileItem file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorForFileType(file.fileExtension);
    final hasPreview = file.previewUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
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
                  // Cover / format block
                  Container(
                    width: 52,
                    height: 72,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: color.withValues(alpha: 0.08),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: hasPreview
                        ? CachedNetworkImage(
                            imageUrl: file.previewUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _formatBadge(color),
                          )
                        : _formatBadge(color),
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
                              fontWeight: FontWeight.w700, fontSize: 14, height: 1.3),
                        ),
                        if (file.authorName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            file.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Format + category chips
                        Row(
                          children: [
                            _chip(file.formatLabel, color, theme),
                            if (file.category != null) ...[
                              const SizedBox(width: 5),
                              _chip(file.category!.name,
                                  theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  theme,
                                  small: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Stats row
                        Row(
                          children: [
                            Icon(PhosphorIconsFill.heart,
                                size: 12, color: SeeUColors.like.withValues(alpha: 0.7)),
                            const SizedBox(width: 3),
                            Text('${file.likesCount}',
                                style: _statStyle(theme)),
                            const SizedBox(width: 10),
                            Icon(PhosphorIconsRegular.download,
                                size: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(width: 3),
                            Text(file.downloadsFormatted, style: _statStyle(theme)),
                            if (file.pagesCount > 0) ...[
                              const SizedBox(width: 10),
                              Icon(PhosphorIconsRegular.fileText,
                                  size: 12,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                              const SizedBox(width: 3),
                              Text('${file.pagesCount} стр.', style: _statStyle(theme)),
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
                child: _readingBadge(file.readingStatus!, theme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _formatBadge(Color color) {
    return Center(
      child: Text(
        file.formatLabel,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, ThemeData theme, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: small ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: small ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : color,
        ),
      ),
    );
  }

  TextStyle _statStyle(ThemeData theme) => TextStyle(
        fontSize: 11,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      );

  Widget _readingBadge(String status, ThemeData theme) {
    Color bg;
    String label;
    switch (status) {
      case 'reading':
        bg = SeeUColors.accent;
        label = 'Читаю';
      case 'done':
        bg = const Color(0xFF43A047);
        label = '✓';
      case 'want':
        bg = const Color(0xFF1E88E5);
        label = 'Хочу';
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
