import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vocsy_epub_viewer/epub_viewer.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_shell.dart';

/// EPUB ридер через vocsy_epub_viewer (нативный FolioReader/R2).
/// Скачивает файл в temp-директорию, затем открывает нативный viewer.
class EpubReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String fileUrl;

  const EpubReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.fileUrl,
  });

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  bool _loading = true;
  String? _error;
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    _openEpub();
  }

  Future<void> _openEpub() async {
    try {
      // Скачиваем в temp
      final tmpDir = await getTemporaryDirectory();
      final filename =
          '${widget.fileId}_${p.basenameWithoutExtension(widget.title)}.epub';
      final localFile = File(p.join(tmpDir.path, filename));

      if (!localFile.existsSync()) {
        final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 3)));
        await dio.download(widget.fileUrl, localFile.path);
      }

      // Загружаем сохранённый прогресс
      final libDio = ref.read(libraryApiClientProvider);
      final progress = await loadProgress(libDio, widget.fileId);
      EpubLocator? lastLocator;
      if (progress != null && progress['cfi'] != null) {
        lastLocator = EpubLocator.fromJson({
          'bookId': widget.fileId,
          'href': progress['cfi'],
          'created': DateTime.now().millisecondsSinceEpoch,
          'locations': {'cfi': progress['cfi']},
        });
      }

      // Настраиваем и открываем viewer
      VocsyEpub.setConfig(
        themeColor: SeeUColors.accent,
        identifier: widget.fileId,
        scrollDirection: EpubScrollDirection.ALLDIRECTIONS,
        allowSharing: true,
        enableTts: false,
        nightMode: false,
      );
      VocsyEpub.open(localFile.path, lastLocation: lastLocator);

      // Подписываемся на обновления позиции
      VocsyEpub.locatorStream.listen((locator) {
        if (locator != null) {
          _positionNotifier.value = {
            'cfi': locator['href'] ?? '',
            'pct': locator['locations']?['progression'] ?? 0,
          };
        }
      });

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString();
      });
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
      docFormat: 'epub',
      positionNotifier: _positionNotifier,
      child: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
                  const SizedBox(height: 12),
                  Text('Не удалось открыть EPUB',
                      style: SeeUTypography.subtitle),
                  const SizedBox(height: 6),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: SeeUTypography.caption.copyWith(color: c.ink3)),
                ],
              ),
            )
          : Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.bookOpen,
                            size: 48, color: c.ink3),
                        const SizedBox(height: 12),
                        Text('EPUB открыт в нативном ридере',
                            style: SeeUTypography.body.copyWith(color: c.ink2)),
                      ],
                    ),
            ),
    );
  }
}
