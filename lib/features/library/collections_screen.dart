import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/collection.dart';
import '../../core/providers/collection_provider.dart';
import 'collection_detail_screen.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(collectionsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Коллекции',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: c.ink,
            )),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: SeeUColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (collections) {
          if (collections.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.bookBookmark,
                      size: 48, color: c.ink4),
                  const SizedBox(height: 16),
                  Text('Нет коллекций',
                      style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Fraunces',
                          color: c.ink2)),
                  const SizedBox(height: 8),
                  Text('Нажмите + чтобы создать первую',
                      style: TextStyle(fontSize: 13, color: c.ink3)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: collections.length,
            itemBuilder: (ctx, i) =>
                _CollectionCard(collection: collections[i]),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая коллекция',
            style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w400)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      await ref
          .read(collectionsProvider.notifier)
          .create(nameCtrl.text.trim(), descCtrl.text.trim());
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}

class _CollectionCard extends ConsumerWidget {
  final Collection collection;
  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.seeuColors;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CollectionDetailScreen(collectionId: collection.id),
      )),
      onLongPress: () => _showOptions(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                alignment: Alignment.center,
                child: collection.filesCount == 0
                    ? Icon(PhosphorIconsRegular.bookBookmark,
                        size: 36, color: c.ink4)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          // Stacked pages effect
                          Positioned(
                            bottom: 16, left: 20,
                            child: _PageMock(color: c.ink4.withValues(alpha: 0.3)),
                          ),
                          Positioned(
                            bottom: 20, left: 16,
                            child: _PageMock(color: c.ink4.withValues(alpha: 0.5)),
                          ),
                          Icon(PhosphorIconsRegular.books,
                              size: 40, color: SeeUColors.accent.withValues(alpha: 0.8)),
                        ],
                      ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${collection.filesCount} файлов',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIconsRegular.pencilSimple,
                  color: context.seeuColors.ink),
              title: const Text('Переименовать'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.trash,
                  color: Colors.red),
              title: const Text('Удалить',
                  style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete' && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Удалить коллекцию?'),
          content:
              Text('«${collection.name}» будет удалена без возможности восстановления.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(collectionsProvider.notifier).delete(collection.id);
      }
    } else if (action == 'edit' && context.mounted) {
      final nameCtrl = TextEditingController(text: collection.name);
      final descCtrl = TextEditingController(text: collection.description);
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Изменить',
              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w400)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Название', border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Описание', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (result == true && nameCtrl.text.trim().isNotEmpty) {
        await ref.read(collectionsProvider.notifier).update(
            collection.id, nameCtrl.text.trim(), descCtrl.text.trim());
      }
      nameCtrl.dispose();
      descCtrl.dispose();
    }
  }
}

class _PageMock extends StatelessWidget {
  final Color color;
  const _PageMock({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}
