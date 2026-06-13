import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'pdf_reader_screen.dart';

/// Промежуточный экран для форматов, конвертируемых в PDF на бэкенде:
/// fb2, docx, rtf, odt, pptx, odp.
///
/// Алгоритм:
///  1. GET /files/:id/pdf — бэкенд конвертирует оригинал через LibreOffice
///     (или отдаёт кэш, если конвертация уже была).
///  2. По получении pdf_url делает pushReplacement на PdfReaderScreen.
///
/// Пользователь видит "Готовим документ..." только при первом открытии
/// каждого файла. Повторные открытия мгновенны (R2-кэш).
class ConvertedPdfReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format;

  const ConvertedPdfReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
  });

  @override
  ConsumerState<ConvertedPdfReaderScreen> createState() =>
      _ConvertedPdfReaderScreenState();
}

class _ConvertedPdfReaderScreenState
    extends ConsumerState<ConvertedPdfReaderScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPdfUrl();
  }

  Future<void> _fetchPdfUrl() async {
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.filePdf(widget.fileId));
      final pdfUrl = resp.data?['data']?['pdf_url'] as String?;
      if (pdfUrl == null || pdfUrl.isEmpty) {
        if (mounted) setState(() => _error = 'Сервер вернул пустой URL PDF');
        return;
      }
      if (!mounted) return;
      // Заменяем текущий экран на PDF-ридер — назад ведёт в библиотеку
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          fileId: widget.fileId,
          title: widget.title,
          fileUrl: pdfUrl,
        ),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIconsRegular.arrowLeft, color: c.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          style: SeeUTypography.subtitle.copyWith(color: c.ink),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _error != null ? _buildError(c) : _buildLoading(c),
    );
  }

  Widget _buildLoading(SeeUThemeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: SeeUColors.accent),
          const SizedBox(height: 20),
          Text(
            'Готовим документ...',
            style: SeeUTypography.body.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 6),
          Text(
            widget.format.toUpperCase(),
            style: SeeUTypography.caption.copyWith(
              color: c.ink3,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(SeeUThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось открыть документ',
                style: SeeUTypography.subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: SeeUTypography.caption.copyWith(color: c.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _fetchPdfUrl();
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
