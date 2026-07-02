import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

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
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(c)),
          // Стеклянный top-bar над PDF: «PDF» kicker + имя файла.
          Align(
            alignment: Alignment.topCenter,
            child: SeeUGlassBar(
              kicker: 'PDF',
              titleText: widget.filename,
              leading: SeeUGlassCircleButton(
                icon: PhosphorIcon(PhosphorIconsRegular.arrowLeft,
                    color: c.ink, size: 20),
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          // Стеклянный page-indicator pill.
          if (_total > 0)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: _PagePill(current: _current, total: _total),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_error != null) {
      return SeeUErrorState(
        title: 'Не удалось загрузить PDF',
        error: _error,
        icon: PhosphorIconsRegular.warning,
        onRetry: () {
          setState(() => _error = null);
          _downloadToCache();
        },
      );
    }
    if (_localPath == null) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
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

/// Стеклянный page-indicator pill поверх PDF.
class _PagePill extends StatelessWidget {
  final int current;
  final int total;
  const _PagePill({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.black.withValues(alpha: 0.28),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: Text(
            '${current + 1} / $total',
            style: SeeUTypography.micro.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
