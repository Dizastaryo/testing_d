import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import 'reader_shell.dart';

/// TEMP build: the native EPUB reader (`vocsy_epub_viewer`) is disabled because
/// its transitive `r2-streamer-kotlin` → NanoHttpd dependency (a jitpack
/// commit-hash version) fails to resolve in the Android build. EPUB files open
/// in an external app instead. PDF/TXT/MD readers are unaffected. Restore the
/// `vocsy_epub_viewer` dependency + the real reader for production once the
/// dependency is pinned.
class EpubReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String fileUrl;
  final String? author;
  final String? coverUrl;

  const EpubReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.fileUrl,
    this.author,
    this.coverUrl,
  });

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.fileUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: 'epub',
      positionNotifier: _positionNotifier,
      // Заглушка: не помечаем книгу «Читаю» и не трекаем прогресс — читать
      // внутри всё равно нельзя.
      trackReading: false,
      child: SeeUEmptyState(
        icon: PhosphorIconsRegular.bookOpen,
        title: 'EPUB-ридер недоступен в этой сборке',
        subtitle: 'Откройте книгу во внешнем приложении для чтения.',
        action: SeeUStateAction(
          label: 'Открыть во внешнем приложении',
          icon: PhosphorIconsRegular.arrowSquareOut,
          onTap: _openExternally,
        ),
      ),
    );
  }
}
