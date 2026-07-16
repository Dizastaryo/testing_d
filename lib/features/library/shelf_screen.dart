import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/reading_provider.dart';
import 'all_bookmarks_screen.dart';
import 'collections_screen.dart';
import 'discover_screen.dart' show LibraryBookRow;
import 'library_design.dart';
import 'my_uploads_screen.dart';
import 'upload_sheet.dart';

/// Полка — всё моё содержимое в одном месте: читаю · хочу · прочитано,
/// плюс быстрый вход в коллекции, закладки, скачанное и мои загрузки.
/// В «Профиле» это не дублируется — там я как читатель.
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key});

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  static const _tabs = ['reading', 'want', 'done'];
  static const _labels = ['Читаю', 'Хочу', 'Прочитано'];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              LibMainBar(
                title: 'Моя полка',
                action: _UploadButton(onDone: () {
                  ref.invalidate(readingStatsProvider);
                  for (final s in _tabs) {
                    ref.invalidate(readingListProvider(s));
                  }
                }),
              ),
              _quickAccess(c),
              const SizedBox(height: 10),
              _tabBar(c),
              Expanded(child: _list()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Быстрый доступ ко всему моему ─────────────────────────────────────────

  Widget _quickAccess(SeeUThemeColors c) {
    final items = <(IconData, Color, String, VoidCallback)>[
      (
        PhosphorIcons.books(),
        SeeUColors.plum,
        'Коллекции',
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CollectionsScreen())),
      ),
      (
        PhosphorIcons.bookmarkSimple(),
        SeeUColors.accent,
        'Закладки',
        () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AllBookmarksScreen())),
      ),
      (
        PhosphorIcons.cloudArrowDown(),
        SeeUColors.success,
        'Скачанное',
        () => context.push('/library/offline'),
      ),
      (
        PhosphorIcons.uploadSimple(),
        SeeUColors.info,
        'Загрузки',
        () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyUploadsScreen())),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Tappable.scaled(
                onTap: items[i].$4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 11),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: LibColors.line(context)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].$1, size: 20, color: items[i].$2),
                      const SizedBox(height: 6),
                      Text(
                        items[i].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Табы «Читаю / Хочу / Прочитано» ───────────────────────────────────────

  Widget _tabBar(SeeUThemeColors c) {
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final counts = [
      (stats['books_reading'] as num?)?.toInt() ?? 0,
      (stats['books_want'] as num?)?.toInt() ?? 0,
      (stats['books_done'] as num?)?.toInt() ?? 0,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: LibColors.line(context))),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              Tappable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tab = i);
                },
                child: Container(
                  padding: const EdgeInsets.only(bottom: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == _tab
                            ? SeeUColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _labels[i],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              i == _tab ? FontWeight.w700 : FontWeight.w600,
                          color: i == _tab ? c.ink : c.ink3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${counts[i]}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Список ────────────────────────────────────────────────────────────────

  Widget _list() {
    final status = _tabs[_tab];
    final async = ref.watch(readingListProvider(status));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _EmptyShelf(
        icon: PhosphorIcons.cloudWarning(),
        title: 'Не удалось загрузить',
        subtitle: 'Проверьте подключение и потяните вниз',
      ),
      data: (files) {
        if (files.isEmpty) return _empty(status);
        return RefreshIndicator(
          color: SeeUColors.accent,
          onRefresh: () async {
            ref.invalidate(readingListProvider(status));
            ref.invalidate(readingStatsProvider);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 28 + context.bottomBarInset),
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _ShelfRow(file: files[i], status: status),
          ),
        );
      },
    );
  }

  Widget _empty(String status) {
    switch (status) {
      case 'want':
        return _EmptyShelf(
          icon: PhosphorIcons.bookmarkSimple(),
          title: 'Пока ничего не отложено',
          subtitle: 'Отмечайте «Хочу» на карточке книги — и она появится здесь',
        );
      case 'done':
        return _EmptyShelf(
          icon: PhosphorIcons.checkCircle(),
          title: 'Ни одной дочитанной',
          subtitle: 'Дочитанные книги собираются здесь и идут в цель года',
        );
      default:
        return _EmptyShelf(
          icon: PhosphorIcons.books(),
          title: 'Библиотека пуста',
          subtitle: 'Загрузи первый файл и он появится здесь',
          action: 'Загрузить файл',
          onAction: () => showUploadSheet(context),
        );
    }
  }
}

/// «+» в шапке полки — единственная точка загрузки файла в библиотеку.
class _UploadButton extends StatelessWidget {
  final VoidCallback onDone;
  const _UploadButton({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: () async {
        final ok = await showUploadSheet(context);
        if (ok) onDone();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SeeUColors.accent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: const Icon(PhosphorIconsBold.plus, size: 17, color: Colors.white),
      ),
    );
  }
}

/// Строка полки: у «читаю» показываем прогресс, у остальных — просто книгу.
class _ShelfRow extends ConsumerWidget {
  final FileItem file;
  final String status;

  const _ShelfRow({required this.file, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (status != 'reading') return LibraryBookRow(file: file);

    final p = ref.watch(readingProgressProvider(file.id)).valueOrNull;
    // Постранично (PDF) — «Стр. X / Y»; текстовые книги (пиксельный offset) —
    // проценты, иначе выходило «Стр. 0 / 15234».
    final String label;
    if (p == null) {
      label = '';
    } else if (p.isPageBased) {
      final page = (p.position['page'] as num?)?.toInt() ?? 0;
      final total = (p.position['total'] as num?)?.toInt() ?? 0;
      label = total > 0 ? 'Стр. $page / $total' : '';
    } else {
      label = '${(p.percentage * 100).toInt()}%';
    }

    return LibraryBookRow(
      file: file,
      progress: p?.percentage ?? 0,
      progressLabel: label,
    );
  }
}

// ─── Пустая полка ───────────────────────────────────────────────────────────

class _EmptyShelf extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;

  const _EmptyShelf({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ListView(
      padding: EdgeInsets.fromLTRB(34, 0, 34, context.bottomBarInset),
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
        if (action != null) ...[
          const SizedBox(height: 24),
          Center(
            child: Tappable.scaled(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsBold.plus,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      action!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
