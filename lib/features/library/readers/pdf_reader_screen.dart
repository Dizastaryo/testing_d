import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
import '../../../core/services/offline_storage_service.dart';
import '../../../core/services/reading_tracker.dart';
import 'pdf_reader_settings.dart';
import 'reader_shell.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String fileUrl;
  final String? author;
  final String? coverUrl;
  /// Оригинальный формат документа (например 'docx', 'pptx').
  /// По умолчанию 'pdf' — показывается в заголовке ридера.
  final String originalFormat;
  /// Только для книг включается трекер чтения (страницы, статистика).
  final bool isBook;

  /// Открыт по закладке → прыгаем на её страницу (1-based), а не на последнюю
  /// прочитанную. null = обычное продолжение чтения.
  final int? initialPage;

  const PdfReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.fileUrl,
    this.author,
    this.coverUrl,
    this.originalFormat = 'pdf',
    this.isBook = false,
    this.initialPage,
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
  ReadingTracker? _tracker;

  /// Resume coordination (fix for the restore race): the page to jump to once
  /// known (null/0 = top), whether the PDF has rendered (pages known), whether
  /// the saved progress has resolved, and whether we already applied the jump.
  int? _resumePage;
  bool _rendered = false;
  bool _progressLoaded = false;
  bool _resumeApplied = false;

  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    if (widget.isBook) {
      _tracker = ReadingTracker(
        actions: ref.read(libraryActionsProvider),
        fileId: widget.fileId,
      );
    }
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
    final actions = ref.read(libraryActionsProvider);
    // Load PDF, reading position and page tracker in parallel.
    final futures = <Future>[
      _loadPdf(),
      actions.loadProgress(widget.fileId),
    ];
    if (_tracker != null) futures.add(_tracker!.init());
    final results = await Future.wait(futures);
    final progress = results[1] as Map<String, dynamic>?;
    if (progress != null) {
      final page = (progress['page'] as num?)?.toInt() ?? 0;
      if (page > 0) _resumePage = page;
    }
    // Открыт по закладке — её страница важнее последней прочитанной.
    if (widget.initialPage != null && widget.initialPage! > 0) {
      _resumePage = widget.initialPage;
    }
    _progressLoaded = true;
    // Progress may resolve before or after onRender — apply exactly once when
    // both the render (pages known) and the saved progress are ready.
    _applyResumeIfReady();
  }

  /// Jumps to the saved page exactly once, only after both the PDF has rendered
  /// and the saved progress has resolved. Safe to call repeatedly.
  void _applyResumeIfReady() {
    if (_resumeApplied) return;
    if (!_rendered || !_progressLoaded) return;
    if (_pdfController == null) return;
    _resumeApplied = true;
    final page = _resumePage ?? 0;
    if (page > 0) _pdfController!.setPage(page);
    _tracker?.startPage(page);
  }

  Future<void> _loadPdf() async {
    try {
      final repo = ref.read(offlineCatalogProvider);
      final path = await repo.ensureAvailable(
        widget.fileId,
        OfflineKind.pdf,
        widget.fileUrl,
        title: widget.title,
        author: widget.author,
        coverUrl: widget.coverUrl,
        originalFormat: widget.originalFormat,
      );
      if (mounted) setState(() => _localPath = path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('DatabaseException')) {
      return 'Ошибка локальной базы данных. Попробуйте перезапустить приложение.';
    }
    if (s.contains('SocketException') || s.contains('Connection refused')) {
      return 'Нет подключения к серверу';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Превышено время ожидания';
    }
    if (s.contains('404')) return 'Файл не найден на сервере';
    return s;
  }

  /// Шит быстрого перехода на страницу.
  Future<void> _showPageJumpDialog() async {
    final result = await showSeeUBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PageJumpSheet(current: _current, total: _total),
    );
    if (result == null || !mounted) return;
    final page = result.clamp(1, _total) - 1; // 0-indexed
    _pdfController?.setPage(page);
  }

  @override
  void dispose() {
    _tracker?.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  /// Key that changes when PDFView-recreating settings change.
  /// flutter_pdfview doesn't support changing params after creation,
  /// so we force a rebuild via Key.
  ValueKey<String> _pdfKey(PdfReaderSettings s) => ValueKey(
        '${s.isNightMode}_${s.isHorizontal}_${s.pageFling}_${s.autoSpacing}',
      );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(pdfReaderSettingsProvider);

    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: widget.originalFormat,
      positionNotifier: _positionNotifier,
      totalPages: _total,
      isPdf: true,
      onGoToPage: (page) =>
          _pdfController?.setPage(page.clamp(1, _total == 0 ? 1 : _total) - 1),
      child: Stack(
        children: [
          // Background color around PDF pages
          ColoredBox(
            color: settings.backgroundColor,
            child: _buildBody(settings),
          ),

          // ── Page reading progress bar (bottom, books only) ─────────────
          if (_total > 0 && _tracker != null)
            Positioned(
              bottom: 50,
              left: 24,
              right: 24,
              child: _PageReadingBar(tracker: _tracker!),
            ),

          // ── Page indicator pill + read count ──────────────────────────
          if (_total > 0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _showPageJumpDialog,
                  // Стеклянный pill: реальный blur подложки + вертикальный
                  // градиент и тонкий светлый бордюр — читается на любом фоне.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
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
                        child: _tracker != null
                            ? ValueListenableBuilder<int>(
                                valueListenable: _tracker!.totalReadPages,
                                builder: (_, readCount, __) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_current + 1} / $_total',
                                      style: SeeUTypography.mono
                                          .copyWith(color: Colors.white),
                                    ),
                                    if (readCount > 0) ...[
                                      Container(
                                        width: 1,
                                        height: 12,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        color: Colors.white24,
                                      ),
                                      Icon(PhosphorIconsFill.checkCircle,
                                          size: 12, color: SeeUColors.success),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$readCount',
                                        style: SeeUTypography.mono.copyWith(
                                          color: SeeUColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : Text(
                                '${_current + 1} / $_total',
                                style: SeeUTypography.mono
                                    .copyWith(color: Colors.white),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(PdfReaderSettings settings) {
    if (_error != null) {
      return SeeUErrorState(
        error: _error,
        title: 'Не удалось загрузить файл',
        onRetry: () {
          setState(() => _error = null);
          _loadPdf();
        },
      );
    }
    if (_localPath == null) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    return PDFView(
      key: _pdfKey(settings),
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: settings.isHorizontal,
      autoSpacing: settings.autoSpacing,
      pageFling: settings.pageFling,
      nightMode: settings.isNightMode,
      onViewCreated: (ctrl) {
        _pdfController = ctrl;
        // Controller can appear after render resolved the progress.
        _applyResumeIfReady();
      },
      onError: (err) {
        if (mounted) setState(() => _error = err.toString());
      },
      onRender: (pages) {
        if (!mounted || pages == null) return;
        setState(() => _total = pages);
        _rendered = true;
        _applyResumeIfReady();
      },
      onPageChanged: (page, total) {
        if (mounted && page != null) {
          setState(() {
            _current = page;
            if (total != null) _total = total;
          });
          _positionNotifier.value = {'page': page, 'total': _total};
          _tracker?.startPage(page);
        }
      },
    );
  }
}

// ─── Page Jump Sheet ─────────────────────────────────────────────────────────

class _PageJumpSheet extends StatefulWidget {
  final int current;
  final int total;
  const _PageJumpSheet({required this.current, required this.total});

  @override
  State<_PageJumpSheet> createState() => _PageJumpSheetState();
}

class _PageJumpSheetState extends State<_PageJumpSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.current + 1}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_ctrl.text.trim());
    Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.listNumbers,
                  size: 20, color: SeeUColors.accent),
              const SizedBox(width: 10),
              Text('Перейти на страницу',
                  style: SeeUTypography.displayS.copyWith(color: c.ink)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: Text(
                  '1 – ${widget.total}',
                  style:
                      SeeUTypography.kicker.copyWith(color: SeeUColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SeeUInput(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            hintText: '1 – ${widget.total}',
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SeeUButton(
                  label: 'Отмена',
                  variant: SeeUButtonVariant.secondary,
                  onTap: () => Navigator.of(context).pop(null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SeeUButton(
                  label: 'Перейти',
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Page Reading Progress Bar ──────────────────────────────────────────────

class _PageReadingBar extends StatelessWidget {
  final ReadingTracker tracker;
  const _PageReadingBar({required this.tracker});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: tracker.currentPageProgress,
      builder: (_, progress, __) => ValueListenableBuilder<bool>(
        valueListenable: tracker.currentPageRead,
        builder: (_, isRead, __) => ValueListenableBuilder<bool>(
          valueListenable: tracker.pageJustRead,
          builder: (_, justRead, __) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                // Светлый полупрозрачный трек — контрастен и на страницах,
                // и на тёмных фонах вокруг них.
                color: Colors.white.withValues(alpha: 0.25),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Background track
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Fill
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: AnimatedContainer(
                      duration: justRead
                          ? const Duration(milliseconds: 400)
                          : const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: isRead
                            ? SeeUColors.success
                            : SeeUColors.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
