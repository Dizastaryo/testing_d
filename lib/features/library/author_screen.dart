import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
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
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Stack(
          children: [
            SeeUErrorState(
              error: '$e',
              onRetry: () => ref.invalidate(authorFilesProvider(authorName)),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SeeUGlassBar(
                kicker: 'Автор',
                titleText: authorName,
                leading: Tappable(
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(PhosphorIconsRegular.arrowLeft,
                        size: 20, color: c.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
        data: (files) => CustomScrollView(
          slivers: [
            // Header with author info — стеклянный collapse
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              expandedHeight: 200,
              leading: IconButton(
                icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: SeeUColors.background.withValues(alpha: 0.72),
                      border: Border(
                        bottom: BorderSide(color: c.line, width: 0.5),
                      ),
                    ),
                    child: FlexibleSpaceBar(
                      background: _AuthorHeader(
                        authorName: authorName,
                        filesCount: files.length,
                        totalLikes: files.fold(0, (s, f) => s + f.likesCount),
                        totalDownloads:
                            files.fold(0, (s, f) => s + f.downloadsCount),
                        totalViews: files.fold(0, (s, f) => s + f.viewsCount),
                        totalRatingsCount:
                            files.fold(0, (s, f) => s + f.ratingsCount),
                        totalRatingsSum:
                            files.fold(0, (s, f) => s + f.ratingsSum),
                      ),
                    ),
                  ),
                ),
              ),
              title: Text(
                authorName,
                style: SeeUTypography.displayS
                    .copyWith(fontSize: 18, color: c.ink),
              ),
            ),

            if (files.isEmpty)
              const SliverFillRemaining(
                child: SeeUEmptyState(
                  icon: PhosphorIconsRegular.userCircle,
                  title: 'Нет файлов',
                  subtitle: 'Файлы автора не найдены',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _AuthorFileCard(file: files[i]),
                    childCount: files.length,
                  ),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
    );
  }
}

class _AuthorHeader extends StatelessWidget {
  final String authorName;
  final int filesCount;
  final int totalLikes;
  final int totalDownloads;
  final int totalViews;
  final int totalRatingsCount;
  final int totalRatingsSum;

  const _AuthorHeader({
    required this.authorName,
    required this.filesCount,
    required this.totalLikes,
    required this.totalDownloads,
    required this.totalViews,
    required this.totalRatingsCount,
    required this.totalRatingsSum,
  });

  double get _avgRating =>
      totalRatingsCount > 0 ? totalRatingsSum / totalRatingsCount : 0;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 56, 20, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Author avatar circle
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: SeeUGradients.heroOrange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: SeeUColors.accent.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _initials(authorName),
                style: SeeUTypography.displayXS
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'АВТОР',
            style: SeeUTypography.kicker.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 12),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniStat(
                icon: PhosphorIconsRegular.files,
                value: '$filesCount',
                label: _filesLabel(filesCount),
              ),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: c.line,
              ),
              _MiniStat(
                icon: PhosphorIconsRegular.heart,
                value: formatCount(totalLikes),
                label: 'лайков',
              ),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: c.line,
              ),
              _MiniStat(
                icon: PhosphorIconsRegular.download,
                value: formatCount(totalDownloads),
                label: 'скачиваний',
              ),
              if (totalViews > 0) ...[
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: c.line,
                ),
                _MiniStat(
                  icon: PhosphorIconsRegular.eye,
                  value: formatCount(totalViews),
                  label: 'просмотров',
                ),
              ],
              if (_avgRating > 0) ...[
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: c.line,
                ),
                _MiniStat(
                  icon: PhosphorIconsRegular.star,
                  value: _avgRating.toStringAsFixed(1),
                  label: 'рейтинг',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _filesLabel(int count) {
    if (count == 1) return 'файл';
    if (count >= 2 && count <= 4) return 'файла';
    return 'файлов';
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c.ink3),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: c.ink3)),
      ],
    );
  }
}

class _AuthorFileCard extends StatelessWidget {
  final FileItem file;
  const _AuthorFileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover with shadow
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Hero(
                tag: 'author_cover_${file.id}',
                child: FileCoverWidget(
                  file: file,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 10,
                ),
              ),
            ),
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
          const SizedBox(height: 3),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colorForFileType(file.fileExtension)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  file.formatLabel,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: colorForFileType(file.fileExtension),
                  ),
                ),
              ),
              const Spacer(),
              if (file.likesCount > 0) ...[
                Icon(PhosphorIconsFill.heart,
                    size: 10,
                    color: SeeUColors.like.withValues(alpha: 0.5)),
                const SizedBox(width: 2),
                Text('${file.likesCount}',
                    style: TextStyle(fontSize: 9, color: c.ink4)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
