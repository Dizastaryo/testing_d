import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_settings.dart';
import 'reader_shell.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String fileUrl;
  /// Оригинальный формат документа (например 'docx', 'pptx').
  /// По умолчанию 'pdf' — показывается в заголовке ридера.
  final String originalFormat;

  const PdfReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.fileUrl,
    this.originalFormat = 'pdf',
  });

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  String? _localPath;
  String? _error;
  int _current = 0;
  int _total = 0;
  PDFViewController? _pdfController;
  // Баг #1: страница из прогресса, применяется в onRender когда контроллер готов
  int? _initialPage;
  bool _savedOffline = false;
  bool _savingOffline = false;

  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await launchUrl(Uri.parse(widget.fileUrl),
            mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    _init();
  }

  Future<File> _offlineFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, '${widget.fileId}.pdf'));
  }

  Future<void> _init() async {
    final dio = ref.read(libraryApiClientProvider);
    // Загружаем PDF и прогресс параллельно.
    // Баг #1 fix: прогресс сохраняем в _initialPage и применяем в onRender,
    // когда _pdfController гарантированно создан.
    final results = await Future.wait([
      _loadPdf(),
      loadProgress(dio, widget.fileId),
    ]);
    final progress = results[1] as Map<String, dynamic>?;
    if (progress != null && mounted) {
      final page = (progress['page'] as num?)?.toInt() ?? 0;
      if (page > 0) _initialPage = page;
    }
  }

  Future<void> _loadPdf() async {
    try {
      // Проверяем офлайн-кэш
      final offlineFile = await _offlineFile();
      if (await offlineFile.exists()) {
        if (mounted) {
          setState(() {
            _localPath = offlineFile.path;
            _savedOffline = true;
          });
        }
        return;
      }

      // Баг #4 fix: имя файла только из fileId, без небезопасного title
      final tmpDir = await getTemporaryDirectory();
      final localFile = File(p.join(tmpDir.path, '${widget.fileId}_tmp.pdf'));
      final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 3)));
      await dio.download(widget.fileUrl, localFile.path);
      if (mounted) setState(() => _localPath = localFile.path);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveOffline() async {
    if (_savingOffline || _savedOffline) return;
    setState(() => _savingOffline = true);
    try {
      final offlineFile = await _offlineFile();
      final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 5)));
      await dio.download(widget.fileUrl, offlineFile.path);
      if (mounted) setState(() => _savedOffline = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл сохранён для офлайн')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить')),
      );
    } finally {
      if (mounted) setState(() => _savingOffline = false);
    }
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final isDark = settings.theme == ReaderTheme.dark;

    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: widget.originalFormat,
      positionNotifier: _positionNotifier,
      child: Stack(
        children: [
          _buildBody(isDark),

          // Индикатор страницы
          if (_total > 0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_current + 1} / $_total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12),
                  ),
                ),
              ),
            ),

          // Кнопка сохранения офлайн
          if (_localPath != null && !_savedOffline)
            Positioned(
              bottom: 60,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: SeeUColors.accent,
                tooltip: 'Сохранить для офлайн',
                onPressed: _savingOffline ? null : _saveOffline,
                child: _savingOffline
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(PhosphorIconsRegular.cloudArrowDown,
                        color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final c = context.seeuColors;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
              const SizedBox(height: 12),
              Text('Не удалось загрузить файл', style: SeeUTypography.subtitle),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _loadPdf();
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    if (_localPath == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Баг #3 fix: используем ТОЛЬКО nightMode — убираем ColorFilter поверх.
    // Раньше были обе инверсии одновременно, что взаимно уничтожалось.
    return PDFView(
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      nightMode: isDark,
      onViewCreated: (ctrl) => _pdfController = ctrl,
      onError: (err) {
        if (mounted) setState(() => _error = err.toString());
      },
      onRender: (pages) {
        if (!mounted || pages == null) return;
        setState(() => _total = pages);
        // Баг #1 fix: применяем сохранённую страницу здесь, когда
        // _pdfController гарантированно инициализирован и PDF отрендерен.
        if (_initialPage != null && _initialPage! > 0) {
          _pdfController?.setPage(_initialPage!);
          _initialPage = null;
        }
      },
      onPageChanged: (page, total) {
        if (mounted && page != null) {
          setState(() {
            _current = page;
            if (total != null) _total = total;
          });
          _positionNotifier.value = {'page': page, 'total': _total};
        }
      },
    );
  }
}
