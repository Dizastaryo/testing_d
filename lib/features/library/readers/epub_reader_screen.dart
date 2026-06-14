import 'dart:async' show StreamSubscription;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vocsy_epub_viewer/epub_viewer.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
import '../../../core/services/offline_storage_service.dart';
import 'reader_settings.dart';
import 'reader_shell.dart';

/// EPUB ридер через vocsy_epub_viewer (нативный FolioReader/R2).
/// Файл хранится постоянно через OfflineCatalogRepository.
/// При первом открытии скачивается; повторные открытия — без сети.
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
  bool _loading = true;
  String? _error;
  StreamSubscription? _locatorSub;
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    // Баг #6 fix: EPUB тоже не поддерживается на Web
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await launchUrl(Uri.parse(widget.fileUrl),
            mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    _openEpub();
  }

  Future<void> _openEpub() async {
    try {
      final repo = ref.read(offlineCatalogProvider);
      final epubPath = await repo.ensureAvailable(
        widget.fileId,
        OfflineKind.epub,
        widget.fileUrl,
        title: widget.title,
        author: widget.author,
        coverUrl: widget.coverUrl,
        originalFormat: 'epub',
      );

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

      // Баг #7 fix: передаём тему ридера в VocsyEpub
      final settings = ref.read(readerSettingsProvider);
      VocsyEpub.setConfig(
        themeColor: SeeUColors.accent,
        identifier: widget.fileId,
        scrollDirection: EpubScrollDirection.ALLDIRECTIONS,
        allowSharing: true,
        enableTts: false,
        nightMode: settings.theme == ReaderTheme.dark,
      );
      VocsyEpub.open(epubPath, lastLocation: lastLocator);

      // Подписываемся на обновления позиции (subscription сохраняется для dispose)
      _locatorSub = VocsyEpub.locatorStream.listen((locator) {
        if (locator != null) {
          _positionNotifier.value = {
            'cfi': locator['href'] ?? '',
            'pct': locator['locations']?['progression'] ?? 0,
          };
        }
      });

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _locatorSub?.cancel();
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
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _openEpub();
                    },
                    child: const Text('Повторить'),
                  ),
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
                            style:
                                SeeUTypography.body.copyWith(color: c.ink2)),
                      ],
                    ),
            ),
    );
  }
}
