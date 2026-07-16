import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/catalog_entry.dart';
import '../../core/providers/offline_catalog_provider.dart';
import '../../core/providers/offline_library_provider.dart';
import '../../core/services/offline_catalog_repository.dart';
import '../../core/services/offline_storage_service.dart';
import '../../core/utils/format.dart';
import 'readers/epub_reader_screen.dart';
import 'readers/pdf_reader_screen.dart';
import 'readers/text_reader_screen.dart';
import 'library_design.dart';

class OfflineLibraryScreen extends ConsumerStatefulWidget {
  const OfflineLibraryScreen({super.key});

  @override
  ConsumerState<OfflineLibraryScreen> createState() =>
      _OfflineLibraryScreenState();
}

class _OfflineLibraryScreenState extends ConsumerState<OfflineLibraryScreen> {
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _bulkMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(offlineLibraryProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(offlineLibraryProvider.notifier).setSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final state = ref.watch(offlineLibraryProvider);
    final totalSize = ref.watch(offlineTotalSizeProvider);

    final topInset = MediaQuery.of(context).padding.top + 72;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: PaperBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: topInset),
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: TextStyle(color: c.ink, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Поиск по названию или автору...',
                  hintStyle: TextStyle(color: c.ink3, fontSize: 14),
                  prefixIcon:
                      Icon(PhosphorIconsRegular.magnifyingGlass, color: c.ink3),
                  filled: true,
                  fillColor: c.surface2,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
  
            // Filter chips
            _FilterBar(
              selected: state.kindFilter,
              onChanged: (kind) =>
                  ref.read(offlineLibraryProvider.notifier).setKindFilter(kind),
            ),
  
            // Sort selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tappable.scaled(
                  onTap: () => _showSortSheet(context, state.sortBy),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(PhosphorIconsRegular.sortAscending,
                            size: 16, color: c.ink3),
                        const SizedBox(width: 6),
                        Text(
                          _sortLabel(state.sortBy),
                          style: SeeUTypography.caption.copyWith(color: c.ink2),
                        ),
                        const SizedBox(width: 4),
                        PhosphorIcon(PhosphorIconsRegular.caretDown,
                            size: 12, color: c.ink3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
  
            // Download queue section
            _DownloadQueueSection(),
  
            // List
            Expanded(
              child: state.error != null && state.items.isEmpty
                  ? SeeUErrorState(
                      error: state.error,
                      onRetry: () =>
                          ref.read(offlineLibraryProvider.notifier).loadInitial(),
                    )
                  : state.isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: SeeUColors.accent))
                  : state.items.isEmpty
                      ? const SeeUEmptyState(
                          icon: PhosphorIconsRegular.cloudArrowDown,
                          title: 'Нет скачанных книг',
                          subtitle: 'Скачанные книги доступны без интернета',
                        )
                      : RefreshIndicator(
                          color: SeeUColors.accent,
                          onRefresh: () =>
                              ref.read(offlineLibraryProvider.notifier).refresh(),
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                state.items.length + (state.isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= state.items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                );
                              }
                              final entry = state.items[index];
                              return _BookCard(
                                entry: entry,
                                isSelected: _selected.contains(entry.fileId),
                                bulkMode: _bulkMode,
                                onTap: () {
                                  if (_bulkMode) {
                                    setState(() {
                                      if (_selected.contains(entry.fileId)) {
                                        _selected.remove(entry.fileId);
                                      } else {
                                        _selected.add(entry.fileId);
                                      }
                                    });
                                  } else {
                                    _openEntry(entry);
                                  }
                                },
                                onLongPress: () {
                                  if (!_bulkMode) {
                                    setState(() {
                                      _bulkMode = true;
                                      _selected.add(entry.fileId);
                                    });
                                  }
                                },
                                onDismissed: () => _deleteEntry(entry.fileId),
                              );
                            },
                          ),
                        ),
            ),
  
            // Footer
            if (!state.isLoading && state.items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.line, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Всего: ${state.totalCount} книг',
                      style: TextStyle(
                          fontSize: 12, color: c.ink3, fontFamily: AppFonts.I.sans),
                    ),
                    const SizedBox(width: 12),
                    totalSize.when(
                      data: (bytes) => Text(
                        formatBytes(bytes),
                        style: TextStyle(
                            fontSize: 12,
                            color: SeeUColors.accent,
                            fontFamily: AppFonts.I.sans,
                            fontWeight: FontWeight.w600),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SeeUGlassBar(
                kicker: _bulkMode ? 'ВЫБОР' : 'ОФЛАЙН',
                title: _bulkMode
                    ? Text('${_selected.length} выбрано',
                        style: SeeUTypography.displayS.copyWith(color: c.ink))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Скачанные',
                              style: SeeUTypography.displayS
                                  .copyWith(color: c.ink)),
                          const SizedBox(width: 8),
                          if (!state.isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    SeeUColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${state.totalCount}',
                                style: SeeUTypography.mono.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: SeeUColors.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: LibBackButton(size: 40),
                ),
                actions: [
                  if (_bulkMode) ...[
                    SeeUGlassCircleButton(
                      icon: PhosphorIcon(PhosphorIconsRegular.trash,
                          color: _selected.isEmpty
                              ? c.ink4
                              : SeeUColors.danger,
                          size: 20),
                      onTap: () {
                        if (_selected.isNotEmpty) _bulkDelete(context);
                      },
                    ),
                    const SizedBox(width: 8),
                    SeeUGlassCircleButton(
                      icon: PhosphorIcon(PhosphorIconsRegular.x,
                          color: c.ink2, size: 20),
                      onTap: () => setState(() {
                        _bulkMode = false;
                        _selected.clear();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(CatalogSortField field) {
    switch (field) {
      case CatalogSortField.savedAt:
        return 'Дата скачивания';
      case CatalogSortField.lastOpenedAt:
        return 'Последнее открытие';
      case CatalogSortField.title:
        return 'Название';
      case CatalogSortField.sizeBytes:
        return 'Размер';
      case CatalogSortField.readingPercent:
        return 'Прогресс';
    }
  }

  void _showSortSheet(BuildContext context, CatalogSortField current) {
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('СОРТИРОВКА',
                  style: SeeUTypography.kicker
                      .copyWith(color: SeeUColors.accent)),
              const SizedBox(height: 4),
              Text('Скачанные',
                  style: SeeUTypography.displayS.copyWith(color: c.ink)),
              const SizedBox(height: 12),
              ...CatalogSortField.values.map((f) {
                final active = f == current;
                return Tappable.scaled(
                  onTap: () {
                    ref.read(offlineLibraryProvider.notifier).setSortBy(f);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: active ? c.accentSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sortLabel(f),
                            style: SeeUTypography.body.copyWith(
                              color: active ? SeeUColors.accent : c.ink,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (active)
                          const PhosphorIcon(PhosphorIconsBold.check,
                              size: 16, color: SeeUColors.accent),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _openEntry(CatalogEntry entry) {
    // Mark as opened, then navigate
    ref.read(offlineCatalogProvider).markOpened(entry.fileId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _OfflineReaderLauncher(entry: entry),
    ));
  }

  Future<void> _deleteEntry(String fileId) async {
    await ref.read(offlineLibraryProvider.notifier).deleteItem(fileId);
    if (mounted) {
      showSeeUSnackBar(context, 'Книга удалена',
          icon: PhosphorIconsRegular.trash);
    }
  }

  Future<void> _bulkDelete(BuildContext ctx) async {
    final ids = _selected.toList();
    setState(() {
      _bulkMode = false;
      _selected.clear();
    });
    await ref.read(offlineLibraryProvider.notifier).deleteItems(ids);
    if (mounted) {
      showSeeUSnackBar(context, 'Удалено ${ids.length} книг',
          icon: PhosphorIconsRegular.trash);
    }
  }
}

// ─── Filter Bar ──────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final OfflineKind? selected;
  final ValueChanged<OfflineKind?> onChanged;
  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final filters = <(OfflineKind?, String)>[
      (null, 'Все'),
      (OfflineKind.pdf, 'PDF'),
      (OfflineKind.epub, 'EPUB'),
      (OfflineKind.text, 'Тексты'),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (kind, label) = filters[i];
          final active = selected == kind;
          return Tappable.scaled(
            onTap: () => onChanged(kind),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? c.accentSoft : c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(
                    color: active ? SeeUColors.accent : c.line),
              ),
              child: Text(
                label,
                style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? SeeUColors.accent : c.ink2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Book Card ──────────────────────────────────────────────────────────────

class _BookCard extends StatelessWidget {
  final CatalogEntry entry;
  final bool isSelected;
  final bool bulkMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDismissed;

  const _BookCard({
    required this.entry,
    required this.isSelected,
    required this.bulkMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final card = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          border: Border.all(
            color: isSelected ? SeeUColors.accent : c.line,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Cover
            _CoverThumbnail(entry: entry),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink),
                  ),
                  if (entry.author != null && entry.author!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: SeeUColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.kind.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: SeeUColors.accent,
                            fontFamily: AppFonts.I.sans,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatBytes(entry.sizeBytes),
                        style: TextStyle(
                          fontSize: 11,
                          color: c.ink4,
                          fontFamily: AppFonts.I.sans,
                        ),
                      ),
                    ],
                  ),
                  if (entry.readingPercent > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: entry.readingPercent.clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor:
                                  SeeUColors.accent.withValues(alpha: 0.12),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  SeeUColors.accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(entry.readingPercent * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: SeeUColors.accent,
                            fontFamily: AppFonts.I.sans,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (bulkMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                activeColor: SeeUColors.accent,
              ),
          ],
        ),
      ),
    );

    if (bulkMode) return card;

    return Dismissible(
      key: ValueKey(entry.fileId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: SeeUColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child:
            const Icon(PhosphorIconsRegular.trash, color: SeeUColors.danger),
      ),
      onDismissed: (_) => onDismissed(),
      child: card,
    );
  }
}

// ─── Cover Thumbnail ────────────────────────────────────────────────────────

class _CoverThumbnail extends StatelessWidget {
  final CatalogEntry entry;
  const _CoverThumbnail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    Widget cover;

    if (entry.coverLocalPath != null &&
        entry.coverLocalPath!.isNotEmpty) {
      final file = File(entry.coverLocalPath!);
      cover = Image.file(
        file,
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(c),
      );
    } else if (entry.coverUrl != null && entry.coverUrl!.isNotEmpty) {
      cover = Image.network(
        entry.coverUrl!,
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(c),
      );
    } else {
      cover = _placeholder(c);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 48, height: 64, child: cover),
    );
  }

  Widget _placeholder(SeeUThemeColors c) {
    return Container(
      width: 48,
      height: 64,
      color: c.surface2,
      child: Center(
        child: Text(
          entry.kind.name.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.ink4,
            fontFamily: AppFonts.I.sans,
          ),
        ),
      ),
    );
  }
}

// ─── Download Queue Section ─────────────────────────────────────────────────

class _DownloadQueueSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(offlineCatalogProvider);
    // Карта fileId → title из каталога, чтобы в очереди показывать
    // человекочитаемое название вместо raw fileId.
    final entries = ref.watch(offlineLibraryProvider).items;
    final titles = {
      for (final e in entries) e.fileId: e.title,
    };
    return StreamBuilder<List<DownloadProgress>>(
      stream: repo.watchQueue(),
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? [];
        final active = tasks.where((t) =>
            t.status == DownloadTaskStatus.queued ||
            t.status == DownloadTaskStatus.downloading ||
            t.status == DownloadTaskStatus.paused);
        if (active.isEmpty) return const SizedBox.shrink();

        final c = context.seeuColors;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: SeeUColors.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: SeeUColors.accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ЗАГРУЗКИ',
                  style: SeeUTypography.kicker.copyWith(color: c.ink2)),
              const SizedBox(height: 6),
              for (final task in active)
                _DownloadTaskRow(
                  task: task,
                  repo: repo,
                  title: titles[task.fileId] ?? 'Файл',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadTaskRow extends StatelessWidget {
  final DownloadProgress task;
  final OfflineCatalogRepository repo;
  final String title;
  const _DownloadTaskRow({
    required this.task,
    required this.repo,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.ink2),
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 3,
                    backgroundColor: c.line,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(SeeUColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (task.status == DownloadTaskStatus.downloading)
            GestureDetector(
              onTap: () => repo.pauseDownload(task.fileId),
              child: Icon(PhosphorIconsRegular.pause,
                  size: 18, color: c.ink3),
            )
          else if (task.status == DownloadTaskStatus.paused)
            GestureDetector(
              onTap: () => repo.resumeDownload(task.fileId),
              child: Icon(PhosphorIconsRegular.play,
                  size: 18, color: SeeUColors.accent),
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => repo.cancelDownload(task.fileId),
            child: Icon(PhosphorIconsRegular.x,
                size: 18, color: SeeUColors.danger),
          ),
        ],
      ),
    );
  }
}

// ─── Offline Reader Launcher ────────────────────────────────────────────────

/// Открывает ридер для оффлайн-книги (без FileItem, напрямую из CatalogEntry).
/// Поскольку readers используют ensureAvailable (которое вернёт localPath
/// из каталога без скачивания), достаточно передать любой URL — он не будет
/// использован для книг, которые уже в каталоге.
class _OfflineReaderLauncher extends StatelessWidget {
  final CatalogEntry entry;
  const _OfflineReaderLauncher({required this.entry});

  @override
  Widget build(BuildContext context) {
    // fileUrl хранится в каталоге; fallback на localPath для уже скачанных
    final url = entry.fileUrl ?? entry.localPath;
    switch (entry.kind) {
      case OfflineKind.pdf:
        return PdfReaderScreen(
          fileId: entry.fileId,
          title: entry.title,
          fileUrl: url,
          author: entry.author,
          coverUrl: entry.coverUrl,
          originalFormat: entry.originalFormat ?? 'pdf',
        );
      case OfflineKind.epub:
        return EpubReaderScreen(
          fileId: entry.fileId,
          title: entry.title,
          fileUrl: url,
          author: entry.author,
          coverUrl: entry.coverUrl,
        );
      case OfflineKind.text:
        return TextReaderScreen(
          fileId: entry.fileId,
          title: entry.title,
          format: entry.originalFormat ?? 'txt',
          fileUrl: url,
          author: entry.author,
          coverUrl: entry.coverUrl,
        );
    }
  }
}
