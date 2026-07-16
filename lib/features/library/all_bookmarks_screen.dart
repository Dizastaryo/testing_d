import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/reading_provider.dart';
import 'library_design.dart';

/// Закладки — все мои отметки по всем книгам. Подстраница «Полки»,
/// открывается единой стрелкой «Назад».
class AllBookmarksScreen extends ConsumerWidget {
  const AllBookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(allBookmarksProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LibBackBar(kicker: 'ПОЛКА', title: 'Закладки'),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: SeeUColors.accent),
                  ),
                  error: (_, __) => _empty(
                    context,
                    PhosphorIcons.cloudWarning(),
                    'Не удалось загрузить',
                    'Проверьте подключение и потяните вниз',
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return _empty(
                        context,
                        PhosphorIcons.bookmarkSimple(),
                        'Закладок пока нет',
                        'Отмечайте важные места прямо в читалке — они соберутся здесь',
                      );
                    }
                    return RefreshIndicator(
                      color: SeeUColors.accent,
                      onRefresh: () async => ref.invalidate(allBookmarksProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _BookmarkRow(entry: items[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String subtitle) {
    final c = context.seeuColors;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      children: [
        const SizedBox(height: 90),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeeUColors.accent.withValues(alpha: 0.1),
            ),
            child: Icon(icon, size: 42, color: SeeUColors.accent),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: SeeUTypography.displayS.copyWith(fontSize: 25, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
        ),
      ],
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  final BookmarkEntry entry;
  const _BookmarkRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final pos = entry.positionLabel;

    return Tappable.scaled(
      onTap: () => context.push('/files/${entry.bookmark.fileId}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 62,
                child: entry.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: entry.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(context),
                      )
                    : _placeholder(context),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.displayS.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (entry.authorName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                  if (entry.bookmark.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.bookmark.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.displayS.copyWith(
                        fontSize: 13,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        color: c.ink2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (pos.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pos,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: SeeUColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        DateFormat('d MMM yyyy', 'ru')
                            .format(entry.bookmark.createdAt),
                        style: TextStyle(fontSize: 11, color: c.ink3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        color: LibColors.chip(context),
        alignment: Alignment.center,
        child: Icon(PhosphorIcons.bookmarkSimple(),
            size: 18, color: context.seeuColors.ink3),
      );
}
