import 'package:cached_network_image/cached_network_image.dart';
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateCollectionSheet(
        onCreated: (name, desc) =>
            ref.read(collectionsProvider.notifier).create(name, desc),
      ),
    );
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
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: _CollectionCover(collection: collection),
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

/// Bottom sheet для создания новой коллекции.
class _CreateCollectionSheet extends StatefulWidget {
  final Future<void> Function(String name, String desc) onCreated;
  const _CreateCollectionSheet({required this.onCreated});

  @override
  State<_CreateCollectionSheet> createState() => _CreateCollectionSheetState();
}

class _CreateCollectionSheetState extends State<_CreateCollectionSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onCreated(_nameCtrl.text.trim(), _descCtrl.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Новая коллекция',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название *',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Описание (необязательно)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            SeeUButton(
              label: _saving ? 'Создание…' : 'Создать',
              onTap: (_saving || _nameCtrl.text.trim().isEmpty) ? null : _submit,
              isLoading: _saving,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

/// Показывает до 4 обложек файлов коллекции в виде 2×2 сетки.
/// Если обложек нет — рисует заглушку с иконкой.
class _CollectionCover extends StatelessWidget {
  final Collection collection;
  const _CollectionCover({required this.collection});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final urls = collection.coverUrls.take(4).toList();

    if (urls.isEmpty) {
      return Container(
        color: c.surface2,
        alignment: Alignment.center,
        child: Icon(
          collection.filesCount == 0
              ? PhosphorIconsRegular.bookBookmark
              : PhosphorIconsRegular.books,
          size: 36,
          color: collection.filesCount == 0 ? c.ink4 : SeeUColors.accent.withValues(alpha: 0.7),
        ),
      );
    }

    if (urls.length == 1) {
      return CachedNetworkImage(
        imageUrl: urls[0],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) => Container(color: c.surface2),
      );
    }

    // 2×2 grid (fill empty cells with surface2)
    final cells = List<String?>.generate(4, (i) => i < urls.length ? urls[i] : null);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
      children: cells.map((url) {
        if (url == null) {
          return Container(color: c.surface2);
        }
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: c.surface2),
        );
      }).toList(),
    );
  }
}
