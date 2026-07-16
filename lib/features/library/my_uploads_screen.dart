import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
import 'edit_file_sheet.dart';
import 'readers/open_reader.dart';
import 'widgets/file_cover_widget.dart';
import 'library_design.dart';

enum _UploadsSort { newest, downloads, views, rating, likes }

extension on _UploadsSort {
  String get label {
    switch (this) {
      case _UploadsSort.newest: return 'Новые';
      case _UploadsSort.downloads: return 'Скачивания';
      case _UploadsSort.views: return 'Просмотры';
      case _UploadsSort.rating: return 'Рейтинг';
      case _UploadsSort.likes: return 'Лайки';
    }
  }

  IconData get icon {
    switch (this) {
      case _UploadsSort.newest: return PhosphorIconsRegular.clockCounterClockwise;
      case _UploadsSort.downloads: return PhosphorIconsRegular.download;
      case _UploadsSort.views: return PhosphorIconsRegular.eye;
      case _UploadsSort.rating: return PhosphorIconsRegular.star;
      case _UploadsSort.likes: return PhosphorIconsRegular.heart;
    }
  }
}

final _uploadsSortProvider = StateProvider<_UploadsSort>((ref) => _UploadsSort.newest);

class MyUploadsScreen extends ConsumerWidget {
  const MyUploadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final userId = ref.watch(authProvider).user?.id ?? '';
    final sort = ref.watch(_uploadsSortProvider);
    final async = ref.watch(userFilesProvider(userId));

    final topInset = MediaQuery.of(context).padding.top + 72;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: PaperBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: async.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: SeeUColors.accent)),
                error: (e, _) => SeeUErrorState(
                  error: e.toString(),
                  onRetry: () => ref.invalidate(userFilesProvider(userId)),
                ),
                data: (files) {
                  if (files.isEmpty) {
                    return const SeeUEmptyState(
                      icon: PhosphorIconsRegular.uploadSimple,
                      title: 'Нет загруженных файлов',
                      subtitle: 'Загрузите файл через библиотеку',
                    );
                  }
                  return _buildContent(context, ref, files, sort, topInset);
                },
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SeeUGlassBar(
                kicker: 'БИБЛИОТЕКА',
                titleText: 'Мои загрузки',
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: LibBackButton(),
                ),
                actions: [
                  SeeUGlassCircleButton(
                    icon: PhosphorIcon(PhosphorIconsRegular.funnel,
                        color: c.ink, size: 20),
                    onTap: () => _showSortSheet(context, ref, sort),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context, WidgetRef ref, _UploadsSort sort) {
    HapticFeedback.selectionClick();
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('СОРТИРОВКА',
                  style: SeeUTypography.kicker
                      .copyWith(color: SeeUColors.accent)),
              const SizedBox(height: 4),
              Text('Мои загрузки',
                  style: SeeUTypography.displayS.copyWith(color: c.ink)),
              const SizedBox(height: 12),
              ..._UploadsSort.values.map((s) {
                final active = s == sort;
                return Tappable.scaled(
                  onTap: () {
                    ref.read(_uploadsSortProvider.notifier).state = s;
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: active ? c.accentSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: Row(
                      children: [
                        PhosphorIcon(s.icon,
                            size: 18,
                            color: active ? SeeUColors.accent : c.ink3),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.label,
                            style: SeeUTypography.body.copyWith(
                              color: active ? SeeUColors.accent : c.ink,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (active)
                          const PhosphorIcon(PhosphorIconsBold.check,
                              size: 16, color: SeeUColors.accent),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref,
      List<FileItem> files, _UploadsSort sort, double topInset) {
    final c = context.seeuColors;
    final userId = ref.watch(authProvider).user?.id ?? '';

    // Apply sort
    final sorted = [...files];
    switch (sort) {
      case _UploadsSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _UploadsSort.downloads:
        sorted.sort((a, b) => b.downloadsCount.compareTo(a.downloadsCount));
      case _UploadsSort.views:
        sorted.sort((a, b) => b.viewsCount.compareTo(a.viewsCount));
      case _UploadsSort.rating:
        sorted.sort((a, b) => b.averageRating.compareTo(a.averageRating));
      case _UploadsSort.likes:
        sorted.sort((a, b) => b.likesCount.compareTo(a.likesCount));
    }

    // Stats header
    final totalDownloads = files.fold(0, (s, f) => s + f.downloadsCount);
    final totalLikes = files.fold(0, (s, f) => s + f.likesCount);
    final totalViews = files.fold(0, (s, f) => s + f.viewsCount);
    final ratedFiles = files.where((f) => f.ratingsCount > 0).toList();
    final avgRating = ratedFiles.isEmpty
        ? 0.0
        : ratedFiles.fold(0.0, (s, f) => s + f.averageRating) /
            ratedFiles.length;

    return Column(
      children: [
        // Stats bar
        Container(
          margin: EdgeInsets.fromLTRB(16, topInset, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: c.line.withValues(alpha: 0.5)),
            boxShadow: SeeUShadows.sm,
          ),
          child: Row(
            children: [
              _StatItem(
                icon: PhosphorIconsFill.files,
                label: 'Файлов',
                value: '${files.length}',
                color: SeeUColors.accent,
              ),
              _divider(c),
              _StatItem(
                icon: PhosphorIconsFill.download,
                label: 'Скачиваний',
                value: formatCount(totalDownloads),
                color: SeeUColors.info,
              ),
              _divider(c),
              _StatItem(
                icon: PhosphorIconsFill.heart,
                label: 'Лайков',
                value: formatCount(totalLikes),
                color: SeeUColors.error,
              ),
              _divider(c),
              _StatItem(
                icon: PhosphorIconsFill.eye,
                label: 'Просмотров',
                value: formatCount(totalViews),
                color: SeeUColors.plum,
              ),
              if (avgRating > 0) ...[
                _divider(c),
                _StatItem(
                  icon: PhosphorIconsFill.star,
                  label: 'Рейтинг',
                  value: avgRating.toStringAsFixed(1),
                  color: SeeUColors.amber,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: SeeUColors.accent,
            onRefresh: () async => ref.invalidate(userFilesProvider(userId)),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _UploadCard(
                file: sorted[i],
                onDeleted: () => ref.invalidate(userFilesProvider(userId)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider(SeeUThemeColors c) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: c.line.withValues(alpha: 0.5),
      );
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontFamily: AppFonts.I.sans,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: c.ink3)),
        ],
      ),
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

    return Dismissible(
      key: ValueKey('upload_${file.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: SeeUColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.trash,
                color: SeeUColors.danger, size: 22),
            const SizedBox(height: 4),
            Text('Удалить',
                style: SeeUTypography.micro
                    .copyWith(color: SeeUColors.danger)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref),
      child: GestureDetector(
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image
              Hero(
                tag: 'upload_cover_${file.id}',
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.download,
                            size: 12, color: c.ink4),
                        const SizedBox(width: 3),
                        Text(file.downloadsFormatted,
                            style: TextStyle(
                                fontSize: 11,
                                color: c.ink3,
                                fontFamily: AppFonts.I.sans)),
                        const SizedBox(width: 10),
                        Icon(PhosphorIconsFill.heart,
                            size: 12,
                            color:
                                SeeUColors.error.withValues(alpha: 0.6)),
                        const SizedBox(width: 3),
                        Text('${file.likesCount}',
                            style: TextStyle(
                                fontSize: 11,
                                color: c.ink3,
                                fontFamily: AppFonts.I.sans)),
                        const SizedBox(width: 10),
                        Icon(PhosphorIconsRegular.eye,
                            size: 12, color: c.ink4),
                        const SizedBox(width: 3),
                        Text(formatCount(file.viewsCount),
                            style: TextStyle(
                                fontSize: 11,
                                color: c.ink3,
                                fontFamily: AppFonts.I.sans)),
                        if (file.ratingsCount > 0) ...[
                          const SizedBox(width: 10),
                          const Icon(PhosphorIconsFill.star,
                              size: 12, color: SeeUColors.amber),
                          const SizedBox(width: 3),
                          Text(file.averageRating.toStringAsFixed(1),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: c.ink3,
                                  fontFamily: AppFonts.I.sans)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Edit button
              GestureDetector(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await showSeeUBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EditFileSheet(file: file),
                  );
                  ref.invalidate(userFilesProvider(file.userId));
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(PhosphorIconsRegular.pencilSimple,
                      color: SeeUColors.accent, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Удалить файл?',
      message:
          '«${file.displayTitle}» будет удалён без возможности восстановления.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIconsRegular.trash,
    );
    if (confirmed) {
      try {
        await ref.read(libraryActionsProvider).deleteFile(file.id);
      } catch (_) {
        // Ошибку удаления раньше проглатывали — Dismissible «удалял» строку
        // визуально, хотя на сервере файл оставался. Теперь откатываем и
        // сообщаем.
        if (context.mounted) {
          showSeeUSnackBar(context, 'Не удалось удалить файл',
              tone: SeeUTone.danger);
        }
        return false;
      }
      onDeleted();
      return true;
    }
    return false;
  }
}
