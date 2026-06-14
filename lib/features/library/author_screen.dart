import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/library_provider.dart';
import 'widgets/file_cover_widget.dart';

class AuthorScreen extends ConsumerWidget {
  final String authorName;
  const AuthorScreen({super.key, required this.authorName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(authorFilesProvider(authorName));

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authorName,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: c.ink,
              ),
            ),
            Text(
              'Автор',
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
          ],
        ),
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
                  Icon(PhosphorIconsRegular.userCircle, size: 48, color: c.ink4),
                  const SizedBox(height: 16),
                  Text('Нет файлов',
                      style: TextStyle(
                          fontFamily: 'Fraunces', fontSize: 17, color: c.ink2)),
                  const SizedBox(height: 6),
                  Text('Файлы автора не найдены',
                      style: TextStyle(fontSize: 13, color: c.ink3)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.55,
            ),
            itemCount: files.length,
            itemBuilder: (ctx, i) {
              final file = files[i];
              return GestureDetector(
                onTap: () => ctx.push('/files/${file.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FileCoverWidget(
                      file: file,
                      width: double.infinity,
                      height: 120,
                      borderRadius: 10,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      file.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file.formatLabel,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
