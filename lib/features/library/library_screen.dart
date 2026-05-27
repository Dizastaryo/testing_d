import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/utils/format.dart';
import '../../core/models/audio_track.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import 'pdf_preview_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _activeCategory = '';
  String _query = '';
  bool _searchOpen = false;
  bool _uploading = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FileItem> _applySearch(List<FileItem> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((f) =>
            f.filename.toLowerCase().contains(q) ||
            f.description.toLowerCase().contains(q) ||
            (f.user?.username.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(fileCategoriesProvider);
    final filesAsync = ref.watch(filesProvider(_activeCategory.isEmpty ? null : _activeCategory));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SeeURadarRefresh(
        onRefresh: () async {
          ref.invalidate(filesProvider);
          ref.invalidate(fileCategoriesProvider);
          await ref.read(filesProvider(
                  _activeCategory.isEmpty ? null : _activeCategory).future);
        },
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(theme)),
          if (_searchOpen) SliverToBoxAdapter(child: _buildSearchField(theme)),
          if (_query.isEmpty) SliverToBoxAdapter(child: _buildUploadZone(theme)),
          // LIB-6: trending hero row — только когда нет активного поиска и категории.
          if (_query.isEmpty && _activeCategory.isEmpty)
            SliverToBoxAdapter(child: _buildTrendingRow(theme)),
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (cats) => _buildCategories(cats, theme),
              loading: () => const SizedBox(height: 50),
              error: (_, __) => const SizedBox(),
            ),
          ),
          filesAsync.when(
            data: (files) {
              final filtered = _applySearch(files);
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Файлов ещё нет'
                            : 'По запросу «$_query» ничего',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                );
              }
              return _buildFileList(filtered, theme);
            },
            loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverToBoxAdapter(
                child: Center(child: Text('Ошибка: $e'))),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Поиск по файлам…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '▮ SHARED DRIVE',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Файлы',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
            icon: Icon(
              _searchOpen ? PhosphorIconsRegular.x : Icons.search,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadZone(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: _uploading ? null : _pickAndUploadFile,
        child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [
            SeeUColors.accent.withValues(alpha: 0.1),
            Colors.amber.withValues(alpha: 0.1),
          ]),
          border: Border.all(
              color: SeeUColors.accent.withValues(alpha: 0.5),
              style: BorderStyle.none),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                    colors: [SeeUColors.accent, Colors.amber]),
                boxShadow: [
                  BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
              ),
              child: const Icon(PhosphorIconsBold.plus, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Загрузить файл',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text('pdf · zip · img · exe · txt',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _uploading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.scaffoldBackgroundColor,
                      ),
                    )
                  : Text(
                      '+ DROP',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: theme.scaffoldBackgroundColor),
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// LIB-7: реальный multipart upload в library. file_picker → MultipartFile
  /// → POST /files/upload (multipart) → invalidate filesProvider.
  /// Backend (file_handler.Upload) validates MIME/size + кладёт в uploads/library/.
  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withReadStream: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать файл')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(picked.bytes!, filename: picked.name),
      });
      await dio.post(
        '/files/upload',
        data: form,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 1),
        ),
      );
      ref.invalidate(filesProvider);
      ref.invalidate(trendingFilesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${picked.name} загружен'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildCategories(List<FileCategory> cats, ThemeData theme) {
    final allCats = [FileCategory(id: '', name: 'Все'), ...cats];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: allCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final isActive = cat.id == _activeCategory;
          return GestureDetector(
            onTap: () => setState(() => _activeCategory = cat.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color:
                    isActive ? theme.colorScheme.onSurface : Colors.transparent,
                border: isActive ? null : Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? theme.scaffoldBackgroundColor
                        : theme.colorScheme.onSurface),
              ),
            ),
          );
        },
      ),
    );
  }

  /// LIB-6: горизонтальный row trending-файлов. Скрыт когда секция пустая
   /// (нет файлов за 7 дней) — не показываем header'а.
   Widget _buildTrendingRow(ThemeData theme) {
     final async = ref.watch(trendingFilesProvider);
     return async.when(
       data: (files) {
         if (files.isEmpty) return const SizedBox.shrink();
         return Padding(
           padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 children: [
                   const Text('🔥', style: TextStyle(fontSize: 16)),
                   const SizedBox(width: 8),
                   Text(
                     'Популярное',
                     style: TextStyle(
                       fontFamily: 'Fraunces',
                       fontSize: 18,
                       fontWeight: FontWeight.w500,
                       color: theme.colorScheme.onSurface,
                     ),
                   ),
                 ],
               ),
               const SizedBox(height: 10),
               SizedBox(
                 height: 92,
                 child: ListView.separated(
                   scrollDirection: Axis.horizontal,
                   itemCount: files.length,
                   separatorBuilder: (_, __) => const SizedBox(width: 10),
                   itemBuilder: (_, i) => _buildTrendingCard(files[i], theme),
                 ),
               ),
             ],
           ),
         );
       },
       loading: () => const SizedBox(height: 80),
       error: (_, __) => const SizedBox.shrink(),
     );
   }

   Widget _buildTrendingCard(FileItem file, ThemeData theme) {
     final color = colorForFileType(file.fileExtension);
     return GestureDetector(
       onTap: () => _onFileTap(file),
       child: Container(
         width: 180,
         padding: const EdgeInsets.all(10),
         decoration: BoxDecoration(
           color: theme.cardColor,
           borderRadius: BorderRadius.circular(12),
           border: Border.all(color: color.withValues(alpha: 0.3)),
         ),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 Container(
                   width: 28,
                   height: 28,
                   decoration: BoxDecoration(
                     color: color.withValues(alpha: 0.15),
                     borderRadius: BorderRadius.circular(6),
                   ),
                   alignment: Alignment.center,
                   child: Text(
                     file.fileExtension.toUpperCase(),
                     style: TextStyle(
                       fontFamily: 'JetBrains Mono',
                       fontSize: 9,
                       fontWeight: FontWeight.w700,
                       color: color,
                     ),
                   ),
                 ),
                 const SizedBox(width: 8),
                 Expanded(
                   child: Text(
                     file.filename,
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                     style: TextStyle(
                       fontSize: 12,
                       fontWeight: FontWeight.w600,
                       color: theme.colorScheme.onSurface,
                     ),
                   ),
                 ),
               ],
             ),
             const Spacer(),
             Row(
               children: [
                 Icon(PhosphorIconsFill.heart,
                     size: 12,
                     color: SeeUColors.like.withValues(alpha: 0.7)),
                 const SizedBox(width: 3),
                 Text('${file.likesCount}',
                     style: TextStyle(
                         fontSize: 10,
                         color: theme.colorScheme.onSurface
                             .withValues(alpha: 0.6))),
                 const SizedBox(width: 8),
                 Icon(Icons.download,
                     size: 12,
                     color: theme.colorScheme.onSurface
                         .withValues(alpha: 0.5)),
                 const SizedBox(width: 3),
                 Text(file.downloadsFormatted,
                     style: TextStyle(
                         fontSize: 10,
                         color: theme.colorScheme.onSurface
                             .withValues(alpha: 0.6))),
               ],
             ),
           ],
         ),
       ),
     );
   }

   Widget _buildFileList(List<FileItem> files, ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildFileCard(files[i], theme),
          ),
          childCount: files.length,
        ),
      ),
    );
  }

  /// LIB-2: audio-файлы играем inline через mini-player; остальные открываем
  /// в file-detail. PDF откроется через inline-preview из detail-screen (LIB-1).
  void _onFileTap(FileItem file) {
    // LIB-1: PDF — inline preview через flutter_pdfview, не file-detail.
    if (file.isPdf) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            url: file.fileUrl,
            filename: file.filename,
          ),
        ),
      );
      return;
    }
    if (file.isAudio) {
      // Конвертируем FileItem → AudioTrack-подобный shape для mini-player.
      // mini-player принимает AudioTrack через playTrack; используем filename
      // как title, автор как artist.
      ref.read(miniPlayerProvider.notifier).play(
            AudioTrack(
              id: file.id,
              title: _stripExtension(file.filename),
              artist: file.user?.username ?? '—',
              audioUrl: file.fileUrl,
              coverUrl: file.previewUrl,
              durationSeconds: 0,
            ),
          );
      return;
    }
    context.push('/files/${file.id}');
  }

  String _stripExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? filename : filename.substring(0, dot);
  }

  Widget _buildFileCard(FileItem file, ThemeData theme) {
    final color = colorForFileType(file.fileExtension);
    final isImage = file.mimeType.startsWith('image/');
    final previewUrl = file.previewUrl.isNotEmpty
        ? file.previewUrl
        : (isImage ? file.fileUrl : '');
    return GestureDetector(
      onTap: () => _onFileTap(file),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            // Inline preview thumbnail. Для image-mime — реальное превью.
            // Для остальных — gradient placeholder с extension-меткой.
            Container(
              width: 46,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: previewUrl.isEmpty
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.15),
                          color.withValues(alpha: 0.05)
                        ])
                    : null,
                color: previewUrl.isEmpty ? null : color.withValues(alpha: 0.05),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: previewUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: previewUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(file.fileExtension.toUpperCase(),
                            style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: color,
                                letterSpacing: 1)),
                      ),
                    )
                  : Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(file.fileExtension.toUpperCase(),
                            style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: color,
                                letterSpacing: 1)),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                      '${file.fileSizeFormatted} · ↓ ${file.downloadsFormatted} · @${file.user?.username ?? ''}',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: file.isPreviewable
                    ? null
                    : theme.colorScheme.surfaceContainerHighest,
                gradient: file.isPreviewable
                    ? LinearGradient(
                        colors: [SeeUColors.accent, Colors.amber])
                    : null,
              ),
              child: Icon(
                file.isPreviewable ? PhosphorIconsRegular.play : Icons.download,
                color: file.isPreviewable
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
