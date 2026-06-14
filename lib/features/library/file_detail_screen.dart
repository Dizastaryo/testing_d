import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';


import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/offline_catalog_provider.dart';
import '../../core/providers/reading_provider.dart';
import '../../core/utils/format.dart' show friendlyError;
import '_file_download_web.dart' if (dart.library.io) '_file_download_io.dart' as downloader;
import 'author_screen.dart';
import 'collection_add_sheet.dart';
import 'readers/open_reader.dart';
import 'widgets/file_cover_widget.dart';

final _fileDetailProvider =
    FutureProvider.autoDispose.family<FileItem, String>((ref, id) async {
  final dio = ref.read(libraryApiClientProvider);
  final r = await dio.get(ApiEndpoints.fileById(id));
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  return FileItem.fromJson(data as Map<String, dynamic>);
});

class FileDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const FileDetailScreen({super.key, required this.id});

  @override
  ConsumerState<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends ConsumerState<FileDetailScreen> {
  bool _downloading = false;
  double _downloadProgress = 0.0; // 0.0–1.0 во время скачивания
  String? _readingStatus; // 'want' | 'reading' | 'done' | null
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadReadingStatus();
  }

  Future<void> _loadReadingStatus() async {
    final status = await ref.read(libraryActionsProvider).getReadingStatus(widget.id);
    if (mounted) setState(() => _readingStatus = status);
  }

  Future<void> _setReadingStatus(String? status) async {
    if (_loadingStatus) return;
    setState(() => _loadingStatus = true);
    try {
      final actions = ref.read(libraryActionsProvider);
      if (status == null || status == _readingStatus) {
        await actions.deleteReadingStatus(widget.id);
        if (mounted) setState(() => _readingStatus = null);
      } else {
        await actions.upsertReadingStatus(widget.id, status);
        if (mounted) setState(() => _readingStatus = status);
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  /// Optimistic toggle. Откат при ошибке через invalidate.
  Future<void> _toggleLike(FileItem file) async {
    final dio = ref.read(libraryApiClientProvider);
    final wasLiked = file.isLiked;
    final url = ApiEndpoints.fileLike(file.id);
    try {
      if (wasLiked) {
        await dio.delete(url);
      } else {
        await dio.post(url);
      }
      // Перечитываем чтобы свежий counter подтянулся.
      ref.invalidate(_fileDetailProvider(file.id));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось: ${e.message ?? e.type}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_fileDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(
            async.valueOrNull?.displayTitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w400,
                fontSize: 20,
                color: c.ink)),
        actions: [
          if (async.valueOrNull != null)
            IconButton(
              icon: Icon(PhosphorIconsRegular.shareFat, color: c.ink2),
              tooltip: 'Поделиться',
              onPressed: () {
                final file = async.value!;
                final info = file.authorName.isNotEmpty
                    ? '${file.displayTitle} — ${file.authorName}'
                    : file.displayTitle;
                Share.share(
                  '$info\n\nОткрыть в SeeU: seeu://files/${file.id}',
                  subject: file.displayTitle,
                );
              },
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось загрузить файл:\n${friendlyError(e)}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (file) => _buildBody(file, c),
      ),
    );
  }

  Widget _buildBody(FileItem file, SeeUThemeColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover — книжные пропорции 2:3, Hero для анимации перехода
          Center(
            child: Hero(
              tag: 'file_cover_${file.id}',
              child: SizedBox(
                width: 160,
                height: 240,
                child: FileCoverWidget(
                  file: file,
                  width: 160,
                  height: 240,
                  borderRadius: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text(
            file.displayTitle,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (file.authorName.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AuthorScreen(authorName: file.authorName),
              )),
              child: Text(
                file.authorName,
                style: TextStyle(
                  fontSize: 14,
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(label: file.formatLabel, color: SeeUColors.accent),
              if (ref.watch(isOfflineProvider(file.id)))
                _Chip(label: 'Офлайн', color: Colors.green),
              _Chip(label: file.fileSizeFormatted),
              _Chip(label: '↓ ${file.downloadsFormatted}'),
              if (file.pagesCount > 0) _Chip(label: '${file.pagesCount} стр.'),
              if (file.likesCount > 0) _Chip(label: '❤ ${file.likesCount}'),
              _Chip(label: DateFormat('d MMM yyyy', 'ru').format(file.createdAt)),
              if (file.category?.name.isNotEmpty == true)
                _Chip(label: file.category!.name),
              if (file.language.isNotEmpty)
                _Chip(label: file.language.toUpperCase()),
            ],
          ),
          if (file.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(file.description, style: TextStyle(color: c.ink2, height: 1.4)),
          ],
          const SizedBox(height: 20),

          // Author
          if (file.user != null)
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: c.surface2,
                  backgroundImage: file.user!.avatarUrl.isNotEmpty
                      ? NetworkImage(file.user!.avatarUrl)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@${file.user!.username}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (file.user!.fullName.isNotEmpty)
                        Text(file.user!.fullName,
                            style: TextStyle(fontSize: 12, color: c.ink2)),
                    ],
                  ),
                ),
              ],
            ),

          // Прогресс чтения — показывается когда файл в статусе "Читаю"
          if (_readingStatus == 'reading' && canRead(file))
            _buildProgressCard(file.id, c),

          // Reading status chips
          if (canRead(file)) ...[
            const SizedBox(height: 16),
            Text('Статус чтения',
                style: TextStyle(fontSize: 12, color: c.ink3, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (key, label) in [
                  ('want', 'Хочу'),
                  ('reading', 'Читаю'),
                  ('done', 'Прочитал(а)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _loadingStatus ? null : () => _setReadingStatus(key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _readingStatus == key
                              ? SeeUColors.accent
                              : c.surface2,
                          border: Border.all(
                            color: _readingStatus == key
                                ? SeeUColors.accent
                                : c.line,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _readingStatus == key ? Colors.white : c.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Похожие файлы (та же категория)
          if (file.categoryId.isNotEmpty)
            _SimilarFilesRow(fileId: file.id, categoryId: file.categoryId),

          // Main action buttons
          Row(
            children: [
              if (canRead(file)) ...[
                Expanded(
                  child: SeeUButton(
                    label: file.readerLabel,
                    onTap: () => openReader(context, file),
                  ),
                ),
                const SizedBox(width: 8),
                // Secondary: download
                GestureDetector(
                  onTap: _downloading ? null : () => _download(file),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(SeeURadii.medium),
                      border: Border.all(color: c.line),
                    ),
                    child: _downloading && _downloadProgress > 0
                        ? Center(
                            child: Text(
                              '${(_downloadProgress * 100).toInt()}%',
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: SeeUColors.accent,
                              ),
                            ),
                          )
                        : _downloading
                            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                            : Icon(PhosphorIconsRegular.download, color: c.ink2, size: 20),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: SeeUButton(
                    label: _downloading && _downloadProgress > 0
                        ? 'Скачивание ${(_downloadProgress * 100).toInt()}%…'
                        : _downloading
                            ? 'Скачивание…'
                            : 'Скачать',
                    isLoading: _downloading && _downloadProgress == 0,
                    onTap: _downloading ? null : () => _download(file),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _toggleLike(file),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: file.isLiked
                        ? SeeUColors.like.withValues(alpha: 0.12)
                        : c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                    border: Border.all(
                      color: file.isLiked
                          ? SeeUColors.like.withValues(alpha: 0.4)
                          : c.line,
                    ),
                  ),
                  child: Icon(
                    file.isLiked
                        ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                        : PhosphorIcons.heart(),
                    color: file.isLiked ? SeeUColors.like : c.ink2,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CollectionAddSheet(fileId: file.id),
                ),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                    border: Border.all(color: c.line),
                  ),
                  child: Icon(PhosphorIconsRegular.bookBookmark,
                      color: c.ink2, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(String fileId, SeeUThemeColors c) {
    final progressAsync = ref.watch(readingProgressProvider(fileId));
    return progressAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (progress) {
        if (progress == null || progress.percentage == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Читаешь',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress.percentage * 100).toInt()}% прочитано',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.percentage,
                    minHeight: 6,
                    backgroundColor: SeeUColors.accent.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(SeeUColors.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress.displayProgress,
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _download(FileItem file) async {
    setState(() { _downloading = true; _downloadProgress = 0.0; });
    try {
      final dio = ref.read(libraryApiClientProvider);
      final r = await dio.get(ApiEndpoints.fileDownload(file.id));
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final url = (data['file_url'] as String?) ?? file.fileUrl;
      final absUrl = url.startsWith('/')
          ? ApiEndpoints.libraryBaseUrl.replaceAll('/api/v1', '') + url
          : url;

      await downloader.saveDownload(
        url: absUrl,
        filename: file.filename,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (!mounted) return;
      ref.invalidate(_fileDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл сохранён')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скачать: ${e.message ?? e.type}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() { _downloading = false; _downloadProgress = 0.0; });
    }
  }
}

class _SimilarFilesRow extends ConsumerWidget {
  final String fileId;
  final String categoryId;
  const _SimilarFilesRow({required this.fileId, required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(
        similarFilesProvider((fileId: fileId, categoryId: categoryId)));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Похожие файлы',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink)),
            const SizedBox(height: 10),
            SizedBox(
              height: 145,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final f = files[i];
                  return GestureDetector(
                    onTap: () => ctx.push('/files/${f.id}'),
                    child: SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FileCoverWidget(
                              file: f, width: 90, height: 112, borderRadius: 8),
                          const SizedBox(height: 4),
                          Text(
                            f.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: c.ink2,
                                height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}
