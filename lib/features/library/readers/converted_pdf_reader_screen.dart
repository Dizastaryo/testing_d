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
///  1. GET /files/:id/pdf
///     - 200 → pdf_url готов, переходим на PdfReaderScreen
///     - 202 → конвертация в очереди, начинаем опрос /pdf-status каждые 3 с
///  2. Когда статус = done → повторяем GET /pdf → открываем ридер
///  3. Когда статус = failed → показываем ошибку
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
  bool _isPolling = false; // true while waiting for background conversion

  @override
  void initState() {
    super.initState();
    _fetchPdfUrl();
  }

  Future<void> _fetchPdfUrl() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _isPolling = false;
    });
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.filePdf(widget.fileId));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final pdfUrl = resp.data?['data']?['pdf_url'] as String?;
        if (pdfUrl == null || pdfUrl.isEmpty) {
          setState(() => _error = 'Сервер вернул пустой URL PDF');
          return;
        }
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            fileId: widget.fileId,
            title: widget.title,
            fileUrl: pdfUrl,
          ),
        ));
      } else if (resp.statusCode == 202) {
        // Background conversion in progress — start polling
        setState(() => _isPolling = true);
        _pollStatus();
      } else {
        final msg = resp.data?['error'] as String? ?? 'Ошибка ${resp.statusCode}';
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pollStatus() async {
    while (mounted && _isPolling && _error == null) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final dio = ref.read(libraryApiClientProvider);
        final resp = await dio.get(ApiEndpoints.filePdfStatus(widget.fileId));
        final status = resp.data?['data']?['status'] as String? ?? 'pending';
        if (status == 'done') {
          // Ready — fetch the actual PDF URL
          setState(() => _isPolling = false);
          _fetchPdfUrl();
          return;
        } else if (status == 'failed') {
          if (mounted) {
            setState(() {
              _isPolling = false;
              _error = 'Конвертация не удалась. Попробуйте позже.';
            });
          }
          return;
        }
        // status = pending | converting — keep polling
      } catch (_) {
        // network glitch — keep polling
      }
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
            _isPolling ? 'Конвертация в очереди...' : 'Готовим документ...',
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
          if (_isPolling) ...[
            const SizedBox(height: 12),
            Text(
              'Можно закрыть и вернуться позже',
              style: SeeUTypography.caption.copyWith(color: c.ink4),
            ),
          ],
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
