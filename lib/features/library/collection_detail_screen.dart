import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_endpoints.dart';
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
    final topInset = MediaQuery.paddingOf(context).top + 68;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => SeeUErrorState(
              error: '$e',
              onRetry: () =>
                  ref.invalidate(collectionDetailProvider(collectionId)),
            ),
            data: (collection) => collection.files.isEmpty
                ? SeeUEmptyState(
                    icon: PhosphorIconsRegular.fileText,
                    title: 'Коллекция пуста',
                    subtitle: 'Добавьте файлы, чтобы они появились здесь',
                    action: SeeUStateAction(
                      label: 'Добавить',
                      icon: PhosphorIconsBold.plus,
                      onTap: () => _showAddFile(context, ref),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, topInset, 16, 32),
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
                          ref.invalidate(
                              collectionDetailProvider(collectionId));
                        },
                      );
                    },
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Коллекция',
              titleText: async.valueOrNull?.name ?? '',
              leading: Tappable(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(PhosphorIconsRegular.arrowLeft,
                      size: 20, color: c.ink),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(PhosphorIconsRegular.plus, color: c.ink),
                  tooltip: 'Добавить файл',
                  onPressed: () => _showAddFile(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFile(BuildContext context, WidgetRef ref) async {
    await showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
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
    final c = context.seeuColors;
    final color = _colorForExt(file.fileExtension);

    return Dismissible(
      key: ValueKey(file.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: SeeUColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child:
            const Icon(PhosphorIconsRegular.trash, color: SeeUColors.danger),
      ),
      confirmDismiss: (_) async {
        onRemove();
        return false;
      },
      child: GestureDetector(
        onTap: () => canRead(file)
            ? openReader(context, file)
            : GoRouter.of(context).push('/files/${file.id}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(SeeURadii.small),
            boxShadow: SeeUShadows.sm,
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
      case 'docx': return SeeUColors.info;
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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _doSearch('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _doSearch(q.trim());
    });
  }

  Future<void> _doSearch(String q) async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.files, queryParameters: {'q': q, 'limit': 30});
      final items = resp.data?['data'] as List? ?? [];
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
    final height = MediaQuery.sizeOf(context).height * 0.7;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: height + bottomInset,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('КОЛЛЕКЦИЯ',
                      style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                  const SizedBox(height: 4),
                  Text('Добавить в коллекцию',
                      style:
                          SeeUTypography.displayS.copyWith(color: c.ink)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SeeUInput(
                controller: _ctrl,
                hintText: 'Поиск по названию…',
                prefix: Icon(PhosphorIconsRegular.magnifyingGlass,
                    size: 18, color: c.ink3),
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _files.isEmpty
                      ? SeeUEmptyState(
                          icon: PhosphorIconsRegular.magnifyingGlass,
                          title: 'Ничего не найдено',
                          iconSize: 48,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _files.length,
                          itemBuilder: (ctx, i) {
                            final f = _files[i];
                            final isAdding = _adding.contains(f.id);
                            return ListTile(
                              leading: Text(f.formatLabel,
                                  style: SeeUTypography.mono.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink2)),
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
