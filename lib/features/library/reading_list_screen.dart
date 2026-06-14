import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/models/reading.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/reading_provider.dart';
import 'readers/open_reader.dart';
import 'widgets/file_cover_widget.dart';

class ReadingListScreen extends ConsumerStatefulWidget {
  const ReadingListScreen({super.key});

  @override
  ConsumerState<ReadingListScreen> createState() => _ReadingListScreenState();
}

class _ReadingListScreenState extends ConsumerState<ReadingListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _tabs = [
    ('reading', 'Читаю'),
    ('want', 'Хочу'),
    ('done', 'Прочитал(а)'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
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
        title: Text('Моя полка',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: c.ink,
            )),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: SeeUColors.accent,
          unselectedLabelColor: c.ink3,
          indicatorColor: SeeUColors.accent,
          tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _tabs
            .map((t) => _ReadingListTab(status: t.$1))
            .toList(),
      ),
    );
  }
}

class _ReadingListTab extends ConsumerWidget {
  final String status;

  const _ReadingListTab({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readingListProvider(status));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (files) {
        if (files.isEmpty) return _buildEmpty(context);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(readingListProvider(status)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _ReadingFileCard(
              file: files[i],
              showProgress: status == 'reading',
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final c = context.seeuColors;
    String message;
    String sub;
    IconData icon;
    switch (status) {
      case 'reading':
        message = 'Ты сейчас ничего не читаешь';
        sub = 'Открой книгу и нажми «Читаю»';
        icon = PhosphorIconsRegular.bookOpen;
      case 'want':
        message = 'Список желаний пуст';
        sub = 'Добавляй книги которые хочешь прочитать';
        icon = PhosphorIconsRegular.bookmarkSimple;
      default:
        message = 'Ты ещё ничего не прочитал(а)';
        sub = 'Здесь появятся прочитанные книги';
        icon = PhosphorIconsRegular.checkCircle;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: c.ink4),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: c.ink2)),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(fontSize: 13, color: c.ink3)),
        ],
      ),
    );
  }
}

class _ReadingFileCard extends ConsumerWidget {
  final FileItem file;
  final bool showProgress;

  const _ReadingFileCard({required this.file, this.showProgress = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.seeuColors;

    // Загружаем прогресс только для вкладки "Читаю"
    final progressAsync = showProgress
        ? ref.watch(readingProgressProvider(file.id))
        : const AsyncData<ReadingProgress?>(null);
    final progress = progressAsync.valueOrNull;

    return GestureDetector(
      onTap: () => canRead(file)
          ? openReader(context, file)
          : context.push('/files/${file.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Обложка с Hero-анимацией
                Hero(
                  tag: 'file_cover_${file.id}',
                  child: FileCoverWidget(
                    file: file,
                    width: 48,
                    height: 64,
                    borderRadius: 8,
                  ),
                ),
                const SizedBox(width: 12),

                // Контент
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14, height: 1.3),
                      ),
                      if (file.authorName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          file.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                      if (showProgress && progress != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              progress.displayProgress,
                              style: const TextStyle(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _relativeTime(progress.lastReadAt),
                              style: TextStyle(fontSize: 10, color: c.ink4),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Иконка действия
                const SizedBox(width: 8),
                if (canRead(file))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      showProgress && progress != null ? 'Продолжить' : 'Читать',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ),
              ],
            ),

            // Прогресс-бар (только для вкладки "Читаю")
            if (showProgress && progress != null && progress.percentage > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.percentage,
                  minHeight: 4,
                  backgroundColor: SeeUColors.accent.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(SeeUColors.accent),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(progress.percentage * 100).toInt()}% прочитано',
                    style: TextStyle(fontSize: 10, color: c.ink3),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
  if (diff.inHours < 24) return '${diff.inHours} ч. назад';
  if (diff.inDays == 1) return 'вчера';
  if (diff.inDays < 7) return '${diff.inDays} дн. назад';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} нед. назад';
  return '${(diff.inDays / 30).floor()} мес. назад';
}
