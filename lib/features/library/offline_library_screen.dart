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

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIconsRegular.arrowLeft, color: c.ink, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: _bulkMode
            ? Text('${_selected.length} выбрано',
                style: TextStyle(color: c.ink, fontSize: 16))
            : Row(
                children: [
                  Text('Скачанные',
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  if (!state.isLoading)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${state.totalCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SeeUColors.accent,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                ],
              ),
        actions: [
          if (_bulkMode) ...[
            IconButton(
              icon: Icon(PhosphorIconsRegular.trash, color: Colors.red),
              onPressed:
                  _selected.isEmpty ? null : () => _bulkDelete(context),
            ),
            IconButton(
              icon: Icon(PhosphorIconsRegular.x, color: c.ink2),
              onPressed: () => setState(() {
                _bulkMode = false;
                _selected.clear();
              }),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                  borderRadius: BorderRadius.circular(12),
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

          // Sort dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.sortAscending,
                    size: 16, color: c.ink3),
                const SizedBox(width: 6),
                DropdownButton<CatalogSortField>(
                  value: state.sortBy,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: c.ink2),
                  items: const [
                    DropdownMenuItem(
                        value: CatalogSortField.savedAt,
                        child: Text('Дата скачивания')),
                    DropdownMenuItem(
                        value: CatalogSortField.lastOpenedAt,
                        child: Text('Последнее открытие')),
                    DropdownMenuItem(
                        value: CatalogSortField.title,
                        child: Text('Название')),
                    DropdownMenuItem(
                        value: CatalogSortField.sizeBytes,
                        child: Text('Размер')),
                    DropdownMenuItem(
                        value: CatalogSortField.readingPercent,
                        child: Text('Прогресс')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(offlineLibraryProvider.notifier)
                          .setSortBy(v);
                    }
                  },
                ),
              ],
            ),
          ),

          // Download queue section
          _DownloadQueueSection(),

          // List
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.items.isEmpty
                    ? _buildEmpty(c)
                    : RefreshIndicator(
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
                        fontSize: 12, color: c.ink3, fontFamily: 'JetBrains Mono'),
                  ),
                  const SizedBox(width: 12),
                  totalSize.when(
                    data: (bytes) => Text(
                      formatBytes(bytes),
                      style: TextStyle(
                          fontSize: 12,
                          color: SeeUColors.accent,
                          fontFamily: 'JetBrains Mono',
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
    );
  }

  Widget _buildEmpty(SeeUThemeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.cloudSlash, size: 56, color: c.ink4),
          const SizedBox(height: 12),
          Text('Нет скачанных книг',
              style: SeeUTypography.subtitle.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          Text('Скачанные книги доступны без интернета',
              style: SeeUTypography.caption.copyWith(color: c.ink4)),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Книга удалена')),
      );
    }
  }

  Future<void> _bulkDelete(BuildContext ctx) async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.of(ctx);
    setState(() {
      _bulkMode = false;
      _selected.clear();
    });
    await ref.read(offlineLibraryProvider.notifier).deleteItems(ids);
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Удалено ${ids.length} книг')),
      );
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
          return GestureDetector(
            onTap: () => onChanged(kind),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? SeeUColors.accent : c.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? SeeUColors.accent : c.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : c.ink2,
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
          borderRadius: BorderRadius.circular(12),
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
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: SeeUColors.accent,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatBytes(entry.sizeBytes),
                        style: TextStyle(
                          fontSize: 11,
                          color: c.ink4,
                          fontFamily: 'JetBrains Mono',
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
                            fontFamily: 'JetBrains Mono',
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
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
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
            fontFamily: 'JetBrains Mono',
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
              Text('Загрузки',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.ink2)),
              const SizedBox(height: 6),
              for (final task in active)
                _DownloadTaskRow(task: task, repo: repo),
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
  const _DownloadTaskRow({required this.task, required this.repo});

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
                  task.fileId.length > 20
                      ? '${task.fileId.substring(0, 20)}...'
                      : task.fileId,
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
            child: Icon(PhosphorIconsRegular.x, size: 18, color: Colors.red),
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
