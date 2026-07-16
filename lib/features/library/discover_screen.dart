import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import 'author_screen.dart';
import 'library_design.dart';
import 'reading_room_screen.dart' show booksCountLabel;

/// Обзор — вкладка поиска и открытий: строка поиска, «Популярное»,
/// «Рекомендации», «Читают друзья», авторы и категории.
///
/// Как только в поиске появляется запрос, витрина уступает место результатам
/// (бесконечный список с курсором) — искать и открывать в одном месте.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_query.isEmpty) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref
          .read(libraryListProvider(LibraryListParams(q: _query)).notifier)
          .load();
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LibMainBar(title: 'Обзор'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: _searchField(c),
              ),
              Expanded(
                child: _query.isEmpty ? _showcase() : _results(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(SeeUThemeColors c) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: LibColors.chip(context),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(PhosphorIcons.magnifyingGlass(), size: 20, color: c.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 14, color: c.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Название, автор, тема…',
                hintStyle: TextStyle(fontSize: 14, color: c.ink3),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            Tappable(
              onTap: () {
                _controller.clear();
                _debounce?.cancel();
                setState(() => _query = '');
              },
              child: Icon(PhosphorIcons.x(), size: 18, color: c.ink3),
            ),
        ],
      ),
    );
  }

  // ── Витрина ───────────────────────────────────────────────────────────────

  Widget _showcase() {
    return RefreshIndicator(
      color: SeeUColors.accent,
      onRefresh: () async {
        ref.invalidate(trendingFilesProvider);
        ref.invalidate(recommendationsProvider);
        ref.invalidate(socialPicksProvider);
        ref.invalidate(popularAuthorsProvider);
        ref.invalidate(fileCategoriesProvider);
      },
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + context.bottomBarInset),
        children: [
          _Shelf(
            pill: const _Pill(
              label: 'Популярное',
              icon: PhosphorIconsFill.fire,
              gradient: LinearGradient(
                colors: [SeeUColors.accent, SeeUColors.accentSecondary],
              ),
            ),
            provider: trendingFilesProvider,
          ),
          const SizedBox(height: 22),
          _Shelf(
            pill: _Pill(
              label: 'Рекомендации',
              icon: PhosphorIconsFill.sparkle,
              color: SeeUColors.plum,
            ),
            provider: recommendationsProvider,
          ),
          const SizedBox(height: 22),
          _Shelf(
            pill: _Pill(
              label: 'Читают друзья',
              icon: PhosphorIconsFill.usersThree,
              color: SeeUColors.info,
            ),
            provider: socialPicksProvider,
          ),
          const SizedBox(height: 22),
          const _AuthorsRow(),
          const SizedBox(height: 22),
          const _CategoryList(),
        ],
      ),
    );
  }

  // ── Результаты поиска ─────────────────────────────────────────────────────

  Widget _results() {
    final c = context.seeuColors;
    final state = ref.watch(libraryListProvider(LibraryListParams(q: _query)));

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorState(
        onRetry: () => ref
            .read(libraryListProvider(LibraryListParams(q: _query)).notifier)
            .load(reset: true),
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(34, 90, 34, context.bottomBarInset),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent.withValues(alpha: 0.1),
              ),
              child: Icon(PhosphorIcons.magnifyingGlass(),
                  size: 40, color: SeeUColors.accent),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Ничего не нашлось',
            textAlign: TextAlign.center,
            style: SeeUTypography.displayS.copyWith(fontSize: 25, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Попробуйте другое название или имя автора',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + context.bottomBarInset),
      itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return LibraryBookRow(file: state.items[i]);
      },
    );
  }
}

// ─── Полка витрины (горизонтальная лента обложек) ───────────────────────────

class _Shelf extends ConsumerWidget {
  final _Pill pill;
  final ProviderListenable<AsyncValue<List<FileItem>>> provider;

  const _Shelf({required this.pill, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(provider).valueOrNull ?? const <FileItem>[];
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pill,
        const SizedBox(height: 14),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _ShelfCard(file: files[i]),
          ),
        ),
      ],
    );
  }
}

class _ShelfCard extends StatelessWidget {
  final FileItem file;
  const _ShelfCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: () => context.push('/files/${file.id}'),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookSpine(file: file, width: 120, height: 160, radius: 12),
            const SizedBox(height: 8),
            Text(
              file.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: c.ink,
              ),
            ),
            if (file.authorName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                file.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Метка раздела витрины: коралловая заливка у «Популярного», мягкая
/// тонированная плашка у остальных.
class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient? gradient;
  final Color? color;

  const _Pill({
    required this.label,
    required this.icon,
    this.gradient,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final solid = gradient != null;
    final tint = color ?? SeeUColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: gradient,
        color: solid ? null : tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: solid ? Colors.white : tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: solid ? Colors.white : tint,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Авторы ─────────────────────────────────────────────────────────────────

class _AuthorsRow extends ConsumerWidget {
  const _AuthorsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final authors = ref.watch(popularAuthorsProvider).valueOrNull ?? const [];
    if (authors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill(
          label: 'Авторы',
          icon: PhosphorIconsFill.pencilLine,
          color: SeeUColors.success,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in authors)
              Tappable.scaled(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AuthorScreen(
                      authorName: a['author_name'] as String? ?? '',
                    ),
                  ),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: LibColors.line(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a['author_name'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${a['files_count'] ?? 0}',
                        style: TextStyle(fontSize: 12, color: c.ink3),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Категории списком ──────────────────────────────────────────────────────

class _CategoryList extends ConsumerWidget {
  const _CategoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final cats = ref.watch(fileCategoriesProvider).valueOrNull ?? const [];
    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibSectionHeader(title: 'Категории'),
        const SizedBox(height: 14),
        for (final cat in cats) ...[
          Tappable.scaled(
            onTap: () =>
                context.push('/library/category/${cat.slug}', extra: cat),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LibColors.line(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cat.colorValue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(cat.iconData,
                        size: 20, color: cat.colorValue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat.name,
                          style: SeeUTypography.displayS.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          booksCountLabel(cat.filesCount),
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                  Icon(PhosphorIcons.caretRight(), size: 15, color: c.ink4),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Строка книги (результаты поиска, полка) ────────────────────────────────

/// Книга строкой: корешок 58×80, серифное название, автор и (если читается)
/// прогресс. Общая для «Обзора» и «Полки».
class LibraryBookRow extends ConsumerWidget {
  final FileItem file;
  final double? progress;
  final String? progressLabel;

  const LibraryBookRow({
    super.key,
    required this.file,
    this.progress,
    this.progressLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;

    return Tappable.scaled(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BookSpine(file: file, width: 58, height: 80, radius: 8),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.displayS.copyWith(
                      fontSize: 16,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    file.authorName.isNotEmpty
                        ? file.authorName
                        : file.formatLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                  const Spacer(),
                  if (progress != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          progressLabel ?? '',
                          style: TextStyle(fontSize: 11, color: c.ink3),
                        ),
                        Text(
                          '${((progress ?? 0) * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: SeeUColors.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LibProgressBar(value: progress!, height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ошибка ─────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.cloudWarning(), size: 58, color: c.ink3),
            const SizedBox(height: 18),
            Text(
              'Не удалось загрузить',
              textAlign: TextAlign.center,
              style:
                  SeeUTypography.displayS.copyWith(fontSize: 23, color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Проверьте подключение и попробуйте снова',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.ink3),
            ),
            const SizedBox(height: 22),
            Tappable.scaled(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: LibColors.line(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.arrowClockwise(),
                        size: 15, color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    const Text(
                      'Повторить',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
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
