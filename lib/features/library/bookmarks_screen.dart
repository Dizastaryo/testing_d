import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/models/reading.dart';
import '../../core/providers/reading_provider.dart';
import 'readers/open_reader.dart';

/// Screen that shows all bookmarks for a given file.
/// Accessible from the file detail screen.
class BookmarksScreen extends ConsumerWidget {
  final String fileId;
  final String fileTitle;

  /// Файл нужен, чтобы тап по закладке открыл ридер на её месте (раньше тап
  /// вообще ничего не делал — фича была write-only).
  final FileItem file;

  const BookmarksScreen({
    super.key,
    required this.fileId,
    required this.fileTitle,
    required this.file,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(bookmarksProvider(fileId));

    final topInset = MediaQuery.of(context).padding.top + 72;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: async.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: SeeUColors.accent)),
              error: (e, _) => SeeUErrorState(
                error: e.toString(),
                onRetry: () => ref.invalidate(bookmarksProvider(fileId)),
              ),
              data: (bookmarks) {
                if (bookmarks.isEmpty) {
                  return SeeUEmptyState(
                    icon: PhosphorIconsRegular.bookmarkSimple,
                    title: 'Нет закладок',
                    subtitle:
                        'Откройте файл и нажмите на иконку закладки чтобы сохранить место',
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, topInset, 16, 16),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _BookmarkCard(
                    bookmark: bookmarks[i],
                    index: i + 1,
                    onTap: () => openReader(ctx, file,
                        jumpTo: bookmarks[i].position),
                    onDelete: () async {
                      HapticFeedback.mediumImpact();
                      final err = await ref
                          .read(bookmarksProvider(fileId).notifier)
                          .deleteBookmark(bookmarks[i].id);
                      if (err != null && context.mounted) {
                        showSeeUSnackBar(context, err, tone: SeeUTone.danger);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SeeUGlassBar(
              leading: SeeUGlassCircleButton(
                icon: PhosphorIcon(PhosphorIconsRegular.arrowLeft,
                    color: c.ink, size: 20),
                onTap: () => Navigator.of(context).pop(),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Закладки',
                      style: SeeUTypography.displayS.copyWith(color: c.ink)),
                  Text(
                    fileTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.caption.copyWith(color: c.ink3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final FileBookmark bookmark;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _BookmarkCard({
    required this.bookmark,
    required this.index,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: SeeUColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(PhosphorIconsRegular.trash,
            color: SeeUColors.danger, size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: c.line.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bookmark number badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SeeUColors.accent, Color(0xFFFF8A65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.I.sans,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Position info
                  Text(
                    _positionLabel(bookmark.position),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (bookmark.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bookmark.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.ink2),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(bookmark.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: c.ink4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIconsRegular.bookmarkSimple,
                size: 18, color: SeeUColors.accent),
          ],
        ),
      ),
      ),
    );
  }

  String _positionLabel(Map<String, dynamic> pos) {
    if (pos.containsKey('page') && pos.containsKey('total')) {
      return 'Страница ${pos['page']} из ${pos['total']}';
    }
    if (pos.containsKey('offset') && pos.containsKey('total')) {
      final total = (pos['total'] as num).toDouble();
      if (total <= 0) return 'Закладка';
      final pct = ((pos['offset'] as num).toDouble() / total * 100).toInt();
      return '$pct% прочитано';
    }
    if (pos.containsKey('pct')) {
      return '${((pos['pct'] as num).toDouble() * 100).toInt()}% прочитано';
    }
    return 'Закладка';
  }

  String _formatDate(DateTime dt) {
    try {
      return DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt);
    } catch (_) {
      return DateFormat('dd.MM.yyyy HH:mm').format(dt);
    }
  }
}
