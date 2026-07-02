import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
import '../../../core/providers/reading_provider.dart';
import '../../../core/services/offline_catalog_repository.dart';
import 'pdf_reader_settings_sheet.dart';
import 'reader_settings_sheet.dart';

/// Общая обёртка для всех ридеров библиотеки.
/// Показывает кастомный AppBar с анимацией скрытия (тап по контенту),
/// тонкий прогресс-бар (% прочитанного) и кнопки закладок/настроек.
/// При dispose сохраняет прогресс через PUT /files/:id/progress.
class ReaderShell extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String docFormat;

  /// Текущая позиция (JSON), устанавливается ридером-потомком.
  final ValueNotifier<Map<String, dynamic>> positionNotifier;
  final Widget child;

  /// Общее число страниц (для PDF ридера) — используется в подсказке о прогрессе.
  final int totalPages;

  /// true для PDF-based ридеров (PDF, конвертированные) —
  /// показывает PdfReaderSettingsSheet вместо текстового.
  final bool isPdf;

  const ReaderShell({
    super.key,
    required this.fileId,
    required this.title,
    required this.docFormat,
    required this.positionNotifier,
    required this.child,
    this.totalPages = 0,
    this.isPdf = false,
  });

  @override
  ConsumerState<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<ReaderShell>
    with WidgetsBindingObserver {
  late final LibraryActions _actions;
  late final OfflineCatalogRepository _offlineCatalog;
  bool _appBarVisible = true;

  /// Periodic background flush so progress survives a crash/kill, not just a
  /// clean dispose. Mirrors ReadingTracker's debounced/background sync.
  Timer? _saveTimer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(libraryActionsProvider);
    _offlineCatalog = ref.read(offlineCatalogProvider);
    WidgetsBinding.instance.addObserver(this);
    // Debounced periodic save while reading.
    _saveTimer = Timer.periodic(
        const Duration(seconds: 18), (_) => _saveProgress());
    _autoSetReadingStatus();
  }

  /// Auto-set status to "reading" if user has no status yet.
  void _autoSetReadingStatus() {
    final current = ref.read(readingStatusProvider(widget.fileId));
    if (current == null) {
      ref.read(readingStatusProvider(widget.fileId).notifier).updateStatus('reading');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save when the app is backgrounded or otherwise loses focus — the reader
    // may never reach dispose() if the OS kills it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    super.dispose();
  }

  void _toggleAppBar() => setState(() => _appBarVisible = !_appBarVisible);

  Future<void> _saveProgress() async {
    if (_saving) return;
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) return;
    _saving = true;
    try {
      // Сохраняем на сервер
      await _actions.saveProgress(widget.fileId, pos);
    } catch (_) {}
    // Сохраняем локально в SQLite каталог
    try {
      final progress = _computeProgress(pos);
      _offlineCatalog.updateProgress(widget.fileId, progress, pos);
    } catch (_) {}
    _saving = false;
  }

  /// Строка с оставшимся прогрессом (страницы или проценты).
  String _progressLabel(Map<String, dynamic> pos) {
    if (pos.isEmpty) return '';
    if (pos.containsKey('page') && pos.containsKey('total')) {
      final page = (pos['page'] as num?)?.toInt() ?? 0;
      final total = (pos['total'] as num?)?.toInt() ?? 0;
      if (total <= 0) return '';
      final remaining = total - page;
      if (remaining <= 0) return 'Прочитано!';
      // 2 min per page avg
      final mins = remaining * 2;
      if (mins < 60) return '~$mins мин. осталось';
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '~$h ч. осталось' : '~$h ч. $m мин. осталось';
    }
    if (pos.containsKey('offset') && pos.containsKey('total')) {
      final offset = (pos['offset'] as num?)?.toDouble() ?? 0;
      final total = (pos['total'] as num?)?.toDouble() ?? 1;
      if (total <= 0) return '';
      final pct = (offset / total * 100).toInt();
      final left = 100 - pct;
      if (left <= 0) return 'Прочитано!';
      return '$pct% · осталось $left%';
    }
    if (pos.containsKey('pct')) {
      final pct = ((pos['pct'] as num?)?.toDouble() ?? 0) * 100;
      return '${pct.toInt()}%';
    }
    return '';
  }

  /// Вычисляет % прочитанного (0.0–1.0) по позиции ридера.
  double _computeProgress(Map<String, dynamic> pos) {
    if (pos.isEmpty) return 0;
    if (pos.containsKey('page') && pos.containsKey('total')) {
      final page = (pos['page'] as num?)?.toInt() ?? 0;
      final total = (pos['total'] as num?)?.toInt() ?? 1;
      return total > 0 ? (page / total).clamp(0.0, 1.0) : 0;
    }
    if (pos.containsKey('offset') && pos.containsKey('total')) {
      final offset = (pos['offset'] as num?)?.toDouble() ?? 0;
      final total = (pos['total'] as num?)?.toDouble() ?? 1;
      return total > 0 ? (offset / total).clamp(0.0, 1.0) : 0;
    }
    if (pos.containsKey('pct')) {
      return ((pos['pct'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: c.bg,
      body: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: widget.positionNotifier,
        builder: (context, pos, _) {
          final progress = _computeProgress(pos);
          // Ридер = immersive. Контент во весь экран; матовая шапка плавает
          // поверх него (реальный BackdropFilter), тап по контенту — toggle.
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleAppBar,
                  child: widget.child,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_appBarVisible,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    offset: _appBarVisible ? Offset.zero : const Offset(0, -1),
                    child: AnimatedOpacity(
                      opacity: _appBarVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: _buildGlassBar(context, c, topPad, progress, pos),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Матовая (frosted-glass) шапка ридера поверх контента: реальный
  /// BackdropFilter (blur ~28) + серифный заголовок + accent-kicker формата +
  /// тонкий прогресс-бар и mono-подсказка.
  Widget _buildGlassBar(BuildContext context, SeeUThemeColors c, double topPad,
      double progress, Map<String, dynamic> pos) {
    final label = _progressLabel(pos);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.72),
            border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: topPad),
              SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.arrowLeft,
                          color: c.ink, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.docFormat.toUpperCase(),
                            style: SeeUTypography.kicker
                                .copyWith(color: SeeUColors.accent),
                          ),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.displayS
                                .copyWith(color: c.ink, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.shareNetwork,
                          color: c.ink2),
                      tooltip: 'Поделиться',
                      onPressed: () => Share.share(
                        'Читаю «${widget.title}» в SeeU\n'
                        'seeu://files/${widget.fileId}',
                        subject: widget.title,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        widget.isPdf
                            ? PhosphorIconsRegular.gear
                            : PhosphorIconsRegular.textAa,
                        color: c.ink2,
                      ),
                      tooltip: 'Настройки',
                      onPressed: () => showSeeUBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => widget.isPdf
                            ? const PdfReaderSettingsSheet()
                            : const ReaderSettingsSheet(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.bookmarkSimple,
                          color: c.ink2),
                      onPressed: () => _addBookmark(context),
                    ),
                  ],
                ),
              ),
              // Тонкий прогресс + mono-подсказка
              if (progress > 0)
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    SeeUColors.accent.withValues(alpha: 0.55),
                  ),
                ),
              if (label.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(label,
                        style: SeeUTypography.mono.copyWith(color: c.ink3)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addBookmark(BuildContext context) async {
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) {
      showSeeUSnackBar(
          context, 'Прокрутите немного, затем добавьте закладку');
      return;
    }

    // Show bottom sheet for optional note
    final note = await showSeeUBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BookmarkNoteSheet(position: pos),
    );

    // null = cancelled, empty string = no note (save anyway)
    if (note == null) return;

    final err = await ref
        .read(bookmarksProvider(widget.fileId).notifier)
        .addBookmark(pos, note);
    if (!context.mounted) return;
    if (err != null) {
      showSeeUSnackBar(context, err, tone: SeeUTone.danger);
    } else {
      showSeeUSnackBar(context, 'Закладка добавлена', tone: SeeUTone.success);
    }
  }
}

// ─── Bookmark Note Sheet ─────────────────────────────────────────────────────

class _BookmarkNoteSheet extends StatefulWidget {
  final Map<String, dynamic> position;
  const _BookmarkNoteSheet({required this.position});

  @override
  State<_BookmarkNoteSheet> createState() => _BookmarkNoteSheetState();
}

class _BookmarkNoteSheetState extends State<_BookmarkNoteSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _positionLabel {
    final pos = widget.position;
    if (pos.containsKey('page') && pos.containsKey('total')) {
      return 'Стр. ${pos['page']} / ${pos['total']}';
    }
    if (pos.containsKey('offset') && pos.containsKey('total')) {
      final total = (pos['total'] as num).toDouble();
      if (total <= 0) return '';
      final pct = ((pos['offset'] as num).toDouble() / total * 100).toInt();
      return '$pct%';
    }
    return '';
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
              Icon(PhosphorIconsFill.bookmarkSimple,
                  size: 20, color: SeeUColors.accent),
              const SizedBox(width: 10),
              Text('Добавить закладку',
                  style: SeeUTypography.displayS.copyWith(color: c.ink)),
              const Spacer(),
              if (_positionLabel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                  ),
                  child: Text(
                    _positionLabel,
                    style: SeeUTypography.kicker
                        .copyWith(color: SeeUColors.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SeeUInput(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            hintText: 'Заметка (необязательно)',
            onSubmitted: (_) => Navigator.of(context).pop(_ctrl.text.trim()),
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
                  label: 'Сохранить',
                  onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Загружает текущий прогресс файла. Возвращает null если нет.
///
/// Тонкая обёртка над [LibraryActions.loadProgress] — сетевые вызовы и парсинг
/// JSON живут в [LibraryActions]. Оставлена для совместимости с epub-ридером.
Future<Map<String, dynamic>?> loadProgress(Dio dio, String fileId) =>
    LibraryActions(dio).loadProgress(fileId);
