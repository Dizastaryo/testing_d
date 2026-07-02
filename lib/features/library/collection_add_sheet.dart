import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/collection.dart';
import '../../core/providers/collection_provider.dart';

/// Bottom sheet that shows user's collections and lets them add a file.
class CollectionAddSheet extends ConsumerStatefulWidget {
  final String fileId;
  const CollectionAddSheet({super.key, required this.fileId});

  @override
  ConsumerState<CollectionAddSheet> createState() => _CollectionAddSheetState();
}

class _CollectionAddSheetState extends ConsumerState<CollectionAddSheet> {
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(collectionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      minChildSize: 0.3,
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
              decoration: BoxDecoration(
                  color: c.ink4, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(PhosphorIconsRegular.bookBookmark,
                        size: 18, color: SeeUColors.accent),
                  ),
                  const SizedBox(width: 10),
                  Text('В коллекцию',
                      style: SeeUTypography.displayXS.copyWith(color: c.ink)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _createNew(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsRegular.plus,
                              size: 14, color: SeeUColors.accent),
                          const SizedBox(width: 4),
                          Text('Новая',
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
              ),
            ),
            Divider(height: 1, color: c.line.withValues(alpha: 0.5)),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Ошибка: $e',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.ink3)),
                  ),
                ),
                data: (collections) {
                  if (collections.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color:
                                  SeeUColors.accent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(PhosphorIconsRegular.bookBookmark,
                                size: 24, color: SeeUColors.accent),
                          ),
                          const SizedBox(height: 16),
                          Text('Нет коллекций',
                              style: SeeUTypography.displayXS
                                  .copyWith(color: c.ink)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _createNew(context),
                            child: Text('Создать первую',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: SeeUColors.accent,
                                )),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: collections.length,
                    itemBuilder: (ctx, i) => _CollectionTile(
                      collection: collections[i],
                      fileId: widget.fileId,
                      busy: _busy,
                      onTap: () => _addToCollection(collections[i].id),
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

  Future<void> _addToCollection(String collectionId) async {
    if (_busy.contains(collectionId)) return;
    HapticFeedback.selectionClick();
    setState(() => _busy.add(collectionId));
    final ok = await ref
        .read(collectionsProvider.notifier)
        .addFile(collectionId, widget.fileId);
    if (mounted) {
      setState(() => _busy.remove(collectionId));
      showSeeUSnackBar(
        context,
        ok ? 'Добавлено в коллекцию' : 'Не удалось добавить',
        tone: ok ? SeeUTone.success : SeeUTone.danger,
        duration: const Duration(seconds: 2),
      );
      if (ok) Navigator.of(context).pop();
    }
  }

  Future<void> _createNew(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Новая коллекция', style: SeeUTypography.displayS),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12))),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      final coll = await ref
          .read(collectionsProvider.notifier)
          .create(nameCtrl.text.trim(), '');
      if (coll != null && mounted) {
        await _addToCollection(coll.id);
      }
    }
    nameCtrl.dispose();
  }
}

class _CollectionTile extends StatelessWidget {
  final Collection collection;
  final String fileId;
  final Set<String> busy;
  final VoidCallback onTap;

  const _CollectionTile({
    required this.collection,
    required this.fileId,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isBusy = busy.contains(collection.id);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SeeUColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(PhosphorIconsRegular.bookBookmark,
            size: 18, color: SeeUColors.accent),
      ),
      title: Text(collection.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        _filesCountLabel(collection.filesCount),
        style: TextStyle(fontSize: 12, color: c.ink3),
      ),
      trailing: isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(PhosphorIconsRegular.plus,
                  size: 16, color: SeeUColors.accent),
            ),
      onTap: isBusy ? null : onTap,
    );
  }

  String _filesCountLabel(int count) {
    if (count == 0) return 'Пусто';
    if (count == 1) return '1 файл';
    if (count >= 2 && count <= 4) return '$count файла';
    return '$count файлов';
  }
}
