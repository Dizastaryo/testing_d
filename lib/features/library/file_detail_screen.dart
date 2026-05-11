import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';
import '_file_download_web.dart' if (dart.library.io) '_file_download_io.dart' as downloader;

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
        title: Text('Файл',
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w400,
                fontSize: 22,
                color: c.ink)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Не удалось загрузить файл: $e')),
        data: (file) => _buildBody(file, c),
      ),
    );
  }

  Widget _buildBody(FileItem file, SeeUThemeColors c) {
    final isImage = file.mimeType.startsWith('image/');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview area
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: isImage && file.previewUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: file.previewUrl,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => _typeIcon(file, big: true),
                    )
                  : isImage && file.fileUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: file.fileUrl,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => _typeIcon(file, big: true),
                        )
                      : _typeIcon(file, big: true),
            ),
          ),

          const SizedBox(height: 16),
          Text(
            file.filename,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(label: file.fileExtension.toUpperCase(), color: SeeUColors.accent),
              _Chip(label: file.fileSizeFormatted),
              _Chip(label: '↓ ${file.downloadsFormatted}'),
              if (file.likesCount > 0) _Chip(label: '❤ ${file.likesCount}'),
              if (file.category?.name.isNotEmpty == true)
                _Chip(label: file.category!.name),
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

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SeeUButton(
                  label: _downloading ? 'Скачивание…' : 'Скачать',
                  isLoading: _downloading,
                  onTap: _downloading ? null : () => _download(file),
                ),
              ),
              const SizedBox(width: 12),
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeIcon(FileItem file, {bool big = false}) {
    final color = _colorForType(file.fileExtension);
    return Center(
      child: Container(
        width: big ? 100 : 60,
        height: big ? 120 : 70,
        padding: EdgeInsets.only(bottom: big ? 14 : 8),
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(big ? 14 : 8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          file.fileExtension.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: big ? 16 : 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Color _colorForType(String ext) {
    switch (ext) {
      case 'pdf':
        return SeeUColors.accent;
      case 'zip':
      case 'rar':
        return const Color(0xFFC04CFD);
      case 'txt':
      case 'md':
        return const Color(0xFF2FA84F);
      case 'mp3':
      case 'wav':
        return const Color(0xFF4A90E2);
      default:
        return Colors.amber;
    }
  }

  Future<void> _download(FileItem file) async {
    setState(() => _downloading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      // Hit /files/:id/download to bump the counter and get the resolved URL.
      final r = await dio.get(ApiEndpoints.fileDownload(file.id));
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final url = (data['file_url'] as String?) ?? file.fileUrl;
      final absUrl = url.startsWith('/')
          ? ApiEndpoints.libraryBaseUrl.replaceAll('/api/v1', '') + url
          : url;

      // Trigger the actual download. On web — invisible anchor click.
      // On mobile — open in external browser.
      try {
        await downloader.saveDownload(url: absUrl, filename: file.filename);
      } catch (_) {
        // Fallback: open the URL.
        final uri = Uri.parse(absUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;
      ref.invalidate(_fileDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скачивание начато')),
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
      if (mounted) setState(() => _downloading = false);
    }
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
