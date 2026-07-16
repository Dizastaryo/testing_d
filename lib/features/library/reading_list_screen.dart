import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    ('done', 'Прочитано'),
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
        actions: [
          IconButton(
            icon: Icon(PhosphorIconsRegular.trophy, size: 22, color: c.ink3),
            tooltip: 'Топ читателей',
            onPressed: () => context.push('/reading/leaderboard'),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Моя полка',
                style: SeeUTypography.displayS.copyWith(color: c.ink)),
            _ReadingStreakBadge(),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: SeeUColors.accent,
          unselectedLabelColor: c.ink3,
          indicatorColor: SeeUColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: _tabs.map((t) {
            final count = ref.watch(readingListProvider(t.$1)).valueOrNull?.length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.$2),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SeeUColors.accent,
                          fontFamily: AppFonts.I.sans,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: Column(
        children: [
          _ReadingActivityHeatmap(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children:
                  _tabs.map((t) => _ReadingListTab(status: t.$1)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reading Streak Badge ─────────────────────────────────────────────────────

class _ReadingStreakBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    // num?.toInt() безопасно и для int, и для double (сервер может прислать
    // 5.0) — прямой `as int?` кидал бы TypeError на double.
    final streak = (stats['reading_streak'] as num?)?.toInt() ?? 0;
    final done = (stats['books_done'] as num?)?.toInt() ?? 0;
    final totalPages = (stats['total_pages_read'] as num?)?.toInt() ?? 0;
    if (streak == 0 && done == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (streak > 0) ...[
            Icon(PhosphorIconsFill.flame,
                size: 12, color: SeeUColors.warning),
            const SizedBox(width: 3),
            Text(
              '$streak дн. подряд',
              style: const TextStyle(
                fontSize: 11,
                color: SeeUColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (done > 0) const SizedBox(width: 10),
          ],
          if (done > 0) ...[
            Icon(PhosphorIconsFill.checkCircle,
                size: 12, color: SeeUColors.success),
            const SizedBox(width: 3),
            Text(
              '$done прочитано',
              style: const TextStyle(
                fontSize: 11,
                color: SeeUColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (totalPages > 0) ...[
            const SizedBox(width: 10),
            Text(
              '${_formatPages(totalPages)} стр.',
              style: TextStyle(
                fontSize: 11,
                color: context.seeuColors.ink3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatPages(int pages) {
    if (pages >= 1000) return '${(pages / 1000).toStringAsFixed(1)}k';
    return '$pages';
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
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Ошибка: $e',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.seeuColors.ink3)),
        ),
      ),
      data: (files) {
        if (files.isEmpty) return _buildEmpty(context);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(readingListProvider(status)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final file = files[i];
              return Dismissible(
                key: ValueKey(file.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: SeeUColors.error,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsRegular.trash,
                          color: Colors.white, size: 20),
                      SizedBox(height: 2),
                      Text('Убрать',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  HapticFeedback.mediumImpact();
                  return true;
                },
                onDismissed: (_) {
                  ref
                      .read(readingStatusProvider(file.id).notifier)
                      .updateStatus(null);
                  ref.invalidate(readingListProvider(status));
                  ref.invalidate(readingStatsProvider);
                },
                child: _ReadingFileCard(
                  file: file,
                  showProgress: status == 'reading',
                ),
              );
            },
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
    Color iconColor;
    switch (status) {
      case 'reading':
        message = 'Ничего не читаешь';
        sub = 'Открой книгу и отметь как «Читаю»';
        icon = PhosphorIconsRegular.bookOpen;
        iconColor = SeeUColors.accent;
      case 'want':
        message = 'Список желаний пуст';
        sub = 'Добавляй книги которые хочешь прочитать';
        icon = PhosphorIconsRegular.bookmarkSimple;
        iconColor = SeeUColors.info;
      default:
        message = 'Ещё ничего не прочитано';
        sub = 'Прочитанные книги появятся здесь';
        icon = PhosphorIconsRegular.checkCircle;
        iconColor = SeeUColors.success;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: 20),
          Text(message,
              style: SeeUTypography.displayXS.copyWith(color: c.ink)),
          const SizedBox(height: 6),
          Text(sub, style: TextStyle(fontSize: 13, color: c.ink3)),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover
                Hero(
                  tag: 'file_cover_${file.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FileCoverWidget(
                      file: file,
                      width: 50,
                      height: 66,
                      borderRadius: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.3),
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
                              style: TextStyle(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppFonts.I.sans,
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

                const SizedBox(width: 8),
                if (canRead(file))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      showProgress && progress != null
                          ? 'Продолжить'
                          : 'Читать',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ),
              ],
            ),

            // Progress bar
            if (showProgress && progress != null && progress.percentage > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.percentage,
                  minHeight: 4,
                  backgroundColor:
                      SeeUColors.accent.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      SeeUColors.accent),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(progress.percentage * 100).toInt()}% прочитано',
                style: TextStyle(fontSize: 10, color: c.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Reading Activity Heatmap ─────────────────────────────────────────────────

class _ReadingActivityHeatmap extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(readingActivityProvider(28));
    final days = async.valueOrNull ?? [];
    if (days.isEmpty) return const SizedBox.shrink();

    final maxSessions = days.fold<int>(
        0, (m, d) => (d['sessions'] as int? ?? 0) > m ? (d['sessions'] as int) : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: c.surface2.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.chartBar, size: 12, color: c.ink4),
              const SizedBox(width: 5),
              Text(
                'Активность за 4 недели',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.ink4,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days.map((d) {
              final sessions = d['sessions'] as int? ?? 0;
              final intensity = maxSessions > 0 ? sessions / maxSessions : 0.0;
              final isToday = (d['date'] as String?) ==
                  DateTime.now().toIso8601String().substring(0, 10);

              Color cellColor;
              if (sessions == 0) {
                cellColor = c.line.withValues(alpha: 0.3);
              } else if (intensity < 0.34) {
                cellColor = SeeUColors.accent.withValues(alpha: 0.3);
              } else if (intensity < 0.67) {
                cellColor = SeeUColors.accent.withValues(alpha: 0.6);
              } else {
                cellColor = SeeUColors.accent;
              }

              return Tooltip(
                message: sessions > 0 ? '$sessions сес.' : '',
                child: Container(
                  width: 8,
                  height: 20,
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(2),
                    border: isToday
                        ? Border.all(color: SeeUColors.accent, width: 1)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
