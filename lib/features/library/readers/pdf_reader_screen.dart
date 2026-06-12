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
import 'reader_shell.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String fileUrl;

  const PdfReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.fileUrl,
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

  Future<void> _init() async {
    // Загружаем прогресс и PDF параллельно
    final dio = ref.read(libraryApiClientProvider);
    final results = await Future.wait([
      _downloadPdf(),
      loadProgress(dio, widget.fileId),
    ]);
    final savedProgress = results[1] as Map<String, dynamic>?;
    if (savedProgress != null && mounted) {
      final page = savedProgress['page'] as int? ?? 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pdfController?.setPage(page);
      });
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final filename =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(widget.title)}.pdf';
      final localFile = File(p.join(tmpDir.path, filename));
      final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 3)));
      await dio.download(widget.fileUrl, localFile.path);
      if (mounted) setState(() => _localPath = localFile.path);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: 'pdf',
      positionNotifier: _positionNotifier,
      child: Stack(
        children: [
          _buildBody(c),
          // Page indicator overlay
          if (_total > 0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        ],
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
              const SizedBox(height: 12),
              Text('Не удалось загрузить PDF', style: SeeUTypography.subtitle),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
            ],
          ),
        ),
      );
    }
    if (_localPath == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PDFView(
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      onViewCreated: (ctrl) => _pdfController = ctrl,
      onError: (err) {
        if (mounted) setState(() => _error = err.toString());
      },
      onRender: (pages) {
        if (mounted && pages != null) setState(() => _total = pages);
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
