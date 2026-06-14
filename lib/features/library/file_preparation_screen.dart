import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
import 'readers/open_reader.dart';

/// Страница слежения за подготовкой файлов к чтению.
///
/// Показывает собственные файлы пользователя форматов FB2/DOCX/RTF/ODT/PPTX/ODP
/// сгруппированные по статусу подготовки. Обновляется каждые 3 секунды.
class FilePreparationScreen extends ConsumerStatefulWidget {
  const FilePreparationScreen({super.key});

  @override
  ConsumerState<FilePreparationScreen> createState() =>
      _FilePreparationScreenState();
}

class _FilePreparationScreenState extends ConsumerState<FilePreparationScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Опрашиваем каждые 3 секунды пока экран открыт
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final userId = ref.read(authProvider).user?.id ?? '';
      if (userId.isNotEmpty) ref.invalidate(userFilesProvider(userId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final userId = ref.watch(authProvider).user?.id ?? '';
    final async = ref.watch(userFilesProvider(userId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Подготовка файлов',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: c.ink,
          ),
        ),
      ),
      body: async.when(
        data: (files) {
          final convertible =
              files.where((f) => f.needsPreparation).toList();

          if (convertible.isEmpty) return _buildEmptyState(c);

          final preparing = convertible
              .where((f) =>
                  f.pdfConversionStatus == 'pending' ||
                  f.pdfConversionStatus == 'converting')
              .toList();
          final failed = convertible
              .where((f) => f.pdfConversionStatus == 'failed')
              .toList();
          final done = convertible
              .where((f) => f.pdfConversionStatus == 'done')
              .toList();
          final queued = convertible
              .where((f) => f.pdfConversionStatus == 'none')
              .toList();

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(userFilesProvider(userId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // Активная подготовка
                if (preparing.isNotEmpty) ...[
                  _sectionHeader('Подготавливается', preparing.length,
                      SeeUColors.accent, spinning: true),
                  const SizedBox(height: 8),
                  ...preparing.map((f) => _FileCard(
                        file: f,
                        status: _PrepStatus.preparing,
                        onRetry: null,
                        onRead: null,
                      )),
                  const SizedBox(height: 20),
                ],
                // В очереди
                if (queued.isNotEmpty) ...[
                  _sectionHeader('В очереди', queued.length,
                      const Color(0xFFFB8C00)),
                  const SizedBox(height: 8),
                  ...queued.map((f) => _FileCard(
                        file: f,
                        status: _PrepStatus.preparing,
                        onRetry: null,
                        onRead: null,
                      )),
                  const SizedBox(height: 20),
                ],
                // Ошибки
                if (failed.isNotEmpty) ...[
                  _sectionHeader('Ошибка', failed.length,
                      const Color(0xFFE53935)),
                  const SizedBox(height: 8),
                  ...failed.map((f) => _FileCard(
                        file: f,
                        status: _PrepStatus.failed,
                        onRetry: () => _retry(f),
                        onRead: null,
                      )),
                  const SizedBox(height: 20),
                ],
                // Готовые
                if (done.isNotEmpty) ...[
                  _sectionHeader('Готово к чтению', done.length,
                      const Color(0xFF43A047)),
                  const SizedBox(height: 8),
                  ...done.map((f) => _FileCard(
                        file: f,
                        status: _PrepStatus.done,
                        onRetry: null,
                        onRead: () => openReader(context, f),
                      )),
                ],
              ],
            ),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(),
              style: SeeUTypography.caption.copyWith(
                  color: context.seeuColors.ink3)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(SeeUThemeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.checkCircle(), size: 56,
              color: const Color(0xFF43A047)),
          const SizedBox(height: 16),
          Text('Все файлы готовы к чтению',
              style: SeeUTypography.subtitle.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          Text('Нет файлов в очереди подготовки',
              style: SeeUTypography.caption.copyWith(color: c.ink3)),
        ],
      ),
    );
  }

  Widget _sectionHeader(
      String title, int count, Color color, {bool spinning = false}) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: context.seeuColors.ink,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        if (spinning) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: color),
          ),
        ],
      ],
    );
  }

  Future<void> _retry(FileItem file) async {
    try {
      // GET /pdf инициирует повторную постановку в очередь (статус failed → pending)
      final dio = ref.read(libraryApiClientProvider);
      await dio.get(ApiEndpoints.filePdf(file.id));
    } catch (_) {}
    final userId = ref.read(authProvider).user?.id ?? '';
    ref.invalidate(userFilesProvider(userId));
  }
}

// ─── Статус карточки ────────────────────────────────────────────────────────

enum _PrepStatus { preparing, done, failed }

class _FileCard extends StatelessWidget {
  final FileItem file;
  final _PrepStatus status;
  final VoidCallback? onRetry;
  final VoidCallback? onRead;

  const _FileCard({
    required this.file,
    required this.status,
    required this.onRetry,
    required this.onRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmtColor = colorForFileType(file.fileExtension);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            // Формат-бейдж
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: fmtColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                file.formatLabel,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: fmtColor,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Название + статус
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusText,
                    style: TextStyle(fontSize: 11, color: _statusColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Действие
            _buildAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildAction() {
    switch (status) {
      case _PrepStatus.preparing:
        return const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: SeeUColors.accent),
        );
      case _PrepStatus.done:
        return GestureDetector(
          onTap: onRead,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Читать',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      case _PrepStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Повторить',
              style: TextStyle(
                color: Color(0xFFE53935),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
    }
  }

  String get _statusText {
    switch (status) {
      case _PrepStatus.preparing:
        return 'Подготавливается к чтению...';
      case _PrepStatus.done:
        return 'Готово к чтению';
      case _PrepStatus.failed:
        return 'Ошибка — не удалось подготовить';
    }
  }

  Color get _statusColor {
    switch (status) {
      case _PrepStatus.done:
        return const Color(0xFF43A047);
      case _PrepStatus.failed:
        return const Color(0xFFE53935);
      case _PrepStatus.preparing:
        return SeeUColors.accent;
    }
  }
}
