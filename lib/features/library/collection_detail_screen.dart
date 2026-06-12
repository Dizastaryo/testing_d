import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/collection_provider.dart';
import '../../core/providers/library_provider.dart';
import 'readers/open_reader.dart';

class CollectionDetailScreen extends ConsumerWidget {
  final String collectionId;
  const CollectionDetailScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(collectionDetailProvider(collectionId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (collection) => NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverAppBar(
              backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
              leading: IconButton(
                icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              title: Text(collection.name,
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: c.ink,
                  )),
              actions: [
                IconButton(
                  icon: Icon(PhosphorIconsRegular.plus, color: c.ink),
                  tooltip: 'Добавить файл',
                  onPressed: () => _showAddFile(context, ref),
                ),
              ],
              floating: true,
              snap: true,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ],
          body: collection.files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.fileText, size: 48, color: c.ink4),
                      const SizedBox(height: 16),
                      Text('Коллекция пуста',
                          style: TextStyle(
                              fontFamily: 'Fraunces', fontSize: 18, color: c.ink2)),
                      const SizedBox(height: 8),
                      Text('Нажмите + чтобы добавить файлы',
                          style: TextStyle(fontSize: 13, color: c.ink3)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: collection.files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final file = collection.files[i];
                    return _FileRow(
                      file: file,
                      onRemove: () async {
                        await ref
                            .read(collectionsProvider.notifier)
                            .removeFile(collection.id, file.id);
                        ref.invalidate(collectionDetailProvider(collectionId));
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _showAddFile(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddFileSheet(
        collectionId: collectionId,
        onAdded: () => ref.invalidate(collectionDetailProvider(collectionId)),
      ),
    );
  }
}

// ─── File row with swipe-to-remove ──────────────────────────────────────────

class _FileRow extends StatelessWidget {
  final FileItem file;
  final VoidCallback onRemove;
  const _FileRow({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForExt(file.fileExtension);

    return Dismissible(
      key: ValueKey(file.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        onRemove();
        return false;
      },
      child: GestureDetector(
        onTap: () => canRead(file)
            ? openReader(context, file)
            : Navigator.of(context).pushNamed('/files/${file.id}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    if (file.authorName.isNotEmpty)
                      Text(
                        file.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.arrowRight,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorForExt(String ext) {
    switch (ext) {
      case 'pdf':  return const Color(0xFFE53935);
      case 'epub': return const Color(0xFF8E24AA);
      case 'fb2':  return const Color(0xFF00ACC1);
      case 'docx': return const Color(0xFF1E88E5);
      case 'pptx': return const Color(0xFFFF7043);
      case 'txt':  return const Color(0xFF43A047);
      default:     return const Color(0xFF78909C);
    }
  }
}

// ─── Add file bottom sheet ───────────────────────────────────────────────────

class _AddFileSheet extends ConsumerStatefulWidget {
  final String collectionId;
  final VoidCallback onAdded;
  const _AddFileSheet({required this.collectionId, required this.onAdded});

  @override
  ConsumerState<_AddFileSheet> createState() => _AddFileSheetState();
}

class _AddFileSheetState extends ConsumerState<_AddFileSheet> {
  final _ctrl = TextEditingController();
  final Set<String> _adding = {};
  List<FileItem> _files = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get('/files', queryParameters: {'q': q, 'limit': 30});
      final items = resp.data?['data']?['items'] as List? ?? [];
      if (mounted) {
        setState(() {
          _files = items
              .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFile(String fileId) async {
    setState(() => _adding.add(fileId));
    await ref
        .read(collectionsProvider.notifier)
        .addFile(widget.collectionId, fileId);
    if (mounted) setState(() => _adding.remove(fileId));
    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration:
                  BoxDecoration(color: c.ink4, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Добавить в коллекцию',
                  style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Поиск по названию…',
                  prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _search,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _files.isEmpty
                      ? Center(
                          child: Text('Ничего не найдено',
                              style: TextStyle(color: c.ink3)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _files.length,
                          itemBuilder: (ctx, i) {
                            final f = _files[i];
                            final isAdding = _adding.contains(f.id);
                            return ListTile(
                              leading: Text(f.formatLabel,
                                  style: const TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                              title: Text(f.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: f.authorName.isNotEmpty
                                  ? Text(f.authorName)
                                  : null,
                              trailing: isAdding
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : IconButton(
                                      icon: const Icon(PhosphorIconsRegular.plus),
                                      color: SeeUColors.accent,
                                      onPressed: () => _addFile(f.id),
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
