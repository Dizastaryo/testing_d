import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/design.dart';

/// LIB-1: inline PDF-preview. На mobile (iOS/Android) использует
/// `flutter_pdfview` — native PDFKit / PdfRenderer. На web — fallback на
/// `url_launcher` (открывает в new tab), потому что нативного pdf-renderer'а
/// нет; web — не production target, см. CLAUDE.md.
///
/// Поток на mobile:
///  1. Cache PDF локально (Dio.download → temp dir; одноразовый /tmp файл).
///  2. PDFView(filePath:...) рендерит весь doc с scroll'ом по страницам.
///  3. Top-app-bar показывает page indicator + Close-button.
class PdfPreviewScreen extends StatefulWidget {
  final String url;
  final String filename;
  const PdfPreviewScreen({
    super.key,
    required this.url,
    required this.filename,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  String? _localPath;
  String? _error;
  int _current = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Web — отдадим юзеру системную «открыть в новой вкладке» через
      // url_launcher и закроем экран.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await launchUrl(Uri.parse(widget.url),
            mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    _downloadToCache();
  }

  Future<void> _downloadToCache() async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final filename =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(widget.filename)}';
      final localFile = File(p.join(tmpDir.path, filename));
      final dio = Dio(BaseOptions(
        receiveTimeout: const Duration(minutes: 2),
      ));
      await dio.download(widget.url, localFile.path);
      if (mounted) setState(() => _localPath = localFile.path);
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
        title: Text(
          widget.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SeeUTypography.subtitle,
        ),
        actions: [
          if (_total > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${_current + 1} / $_total',
                  style: SeeUTypography.caption.copyWith(color: c.ink2),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(c),
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
              Text('Не удалось загрузить PDF',
                  style: SeeUTypography.subtitle),
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
        }
      },
    );
  }
}
