import 'package:flutter/material.dart';
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
                  Text('Добавить в коллекцию',
                      style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: c.ink)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _createNew(context),
                    icon: const Icon(PhosphorIconsRegular.plus, size: 16),
                    label: const Text('Новая'),
                    style: TextButton.styleFrom(
                        foregroundColor: SeeUColors.accent),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Ошибка: $e')),
                data: (collections) {
                  if (collections.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsRegular.bookBookmark,
                              size: 40, color: c.ink4),
                          const SizedBox(height: 12),
                          Text('Нет коллекций',
                              style: TextStyle(color: c.ink3)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => _createNew(context),
                            child: const Text('Создать первую'),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: collections.length,
                    itemBuilder: (ctx, i) =>
                        _CollectionTile(
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
    setState(() => _busy.add(collectionId));
    final ok = await ref
        .read(collectionsProvider.notifier)
        .addFile(collectionId, widget.fileId);
    if (mounted) {
      setState(() => _busy.remove(collectionId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Добавлено в коллекцию' : 'Не удалось добавить'),
          duration: const Duration(seconds: 2),
        ),
      );
      if (ok) Navigator.of(context).pop();
    }
  }

  Future<void> _createNew(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая коллекция',
            style: TextStyle(
                fontFamily: 'Fraunces', fontWeight: FontWeight.w400)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
              labelText: 'Название', border: OutlineInputBorder()),
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
          color: SeeUColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Icon(PhosphorIconsRegular.bookBookmark,
            size: 18, color: SeeUColors.accent),
      ),
      title: Text(collection.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${collection.filesCount} файлов',
          style: TextStyle(fontSize: 12, color: c.ink3)),
      trailing: isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(PhosphorIconsRegular.plus, color: SeeUColors.accent),
      onTap: isBusy ? null : onTap,
    );
  }
}
