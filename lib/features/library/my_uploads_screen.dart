import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
import 'readers/open_reader.dart';

class MyUploadsScreen extends ConsumerWidget {
  const MyUploadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final userId = ref.watch(authProvider).user?.id ?? '';
    final async = ref.watch(userFilesProvider(userId));

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
        title: Text('Мои загрузки',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: c.ink,
            )),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (files) {
          if (files.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.uploadSimple, size: 48, color: c.ink4),
                  const SizedBox(height: 16),
                  Text('Нет загруженных файлов',
                      style: TextStyle(
                          fontFamily: 'Fraunces', fontSize: 18, color: c.ink2)),
                  const SizedBox(height: 8),
                  Text('Загрузите файл через библиотеку',
                      style: TextStyle(fontSize: 13, color: c.ink3)),
                ],
              ),
            );
          }

          // Stats header
          final totalDownloads = files.fold(0, (s, f) => s + f.downloadsCount);
          final totalLikes = files.fold(0, (s, f) => s + f.likesCount);

          return Column(
            children: [
              // Stats bar
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(label: 'Файлов', value: '${files.length}'),
                    _StatItem(label: 'Скачиваний', value: formatCount(totalDownloads)),
                    _StatItem(label: 'Лайков', value: formatCount(totalLikes)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(userFilesProvider(userId)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _UploadCard(
                      file: files[i],
                      onDeleted: () => ref.invalidate(userFilesProvider(userId)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SeeUColors.accent)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }
}

class _UploadCard extends ConsumerWidget {
  final FileItem file;
  final VoidCallback onDeleted;
  const _UploadCard({required this.file, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final color = _colorForExt(file.fileExtension);

    return GestureDetector(
      onTap: () => canRead(file)
          ? openReader(context, file)
          : Navigator.of(context).pushNamed('/files/${file.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Format badge
            Container(
              width: 44,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                file.formatLabel,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 8,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (file.authorName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      file.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.download,
                          size: 12, color: c.ink3),
                      const SizedBox(width: 3),
                      Text(file.downloadsFormatted,
                          style: TextStyle(fontSize: 11, color: c.ink3)),
                      const SizedBox(width: 10),
                      Icon(PhosphorIconsRegular.heart, size: 12, color: c.ink3),
                      const SizedBox(width: 3),
                      Text('${file.likesCount}',
                          style: TextStyle(fontSize: 11, color: c.ink3)),
                    ],
                  ),
                ],
              ),
            ),
            // Delete button
            IconButton(
              icon: const Icon(PhosphorIconsRegular.trash, color: Colors.red, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text('«${file.displayTitle}» будет удалён без возможности восстановления.'),
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
      await ref.read(libraryActionsProvider).deleteFile(file.id);
      onDeleted();
    }
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
