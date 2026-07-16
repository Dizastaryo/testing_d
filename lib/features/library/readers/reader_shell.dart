import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
import '../../../core/providers/reading_provider.dart';
import '../../../core/services/offline_catalog_repository.dart';
import '../library_design.dart';
import 'pdf_reader_settings_sheet.dart';
import 'reader_settings.dart';
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

  /// Переход к странице (1-индексная) — из настроек PDF. Задаёт PDF-ридер,
  /// у которого есть контроллер полотна.
  final ValueChanged<int>? onGoToPage;

  /// Отслеживать чтение: авто-статус «Читаю» + периодическое сохранение
  /// прогресса. false для ридеров-заглушек (EPUB), которые фактически ничего
  /// не читают — иначе простое открытие помечало книгу «Читаю» и искажало
  /// статистику, а прогресс всё равно оставался пустым.
  final bool trackReading;

  const ReaderShell({
    super.key,
    required this.fileId,
    required this.title,
    required this.docFormat,
    required this.positionNotifier,
    required this.child,
    this.totalPages = 0,
    this.isPdf = false,
    this.onGoToPage,
    this.trackReading = true,
  });

  @override
  ConsumerState<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<ReaderShell>
    with WidgetsBindingObserver {
  late final LibraryActions _actions;
  late final OfflineCatalogRepository _offlineCatalog;
  bool _appBarVisible = true;

  /// Пилюля «тап — показать панель»: показывается один раз за сессию ридера
  /// при первом скрытии панели и сама гаснет через 2.5 с.
  bool _hintShown = false;
  bool _hintVisible = false;
  Timer? _hintTimer;

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
    // Ридеры-заглушки (EPUB) не трекают: ни авто-статуса, ни сохранения.
    if (widget.trackReading) {
      // Debounced periodic save while reading.
      _saveTimer = Timer.periodic(
          const Duration(seconds: 18), (_) => _saveProgress());
      _autoSetReadingStatus();
    }
  }

  /// Auto-set status to "reading" — но не затирая уже проставленный статус.
  /// Логика ждёт загрузки статуса внутри нотифаера (см. autoSetReadingIfAbsent),
  /// иначе гонка демотировала «Прочитано» до «Читаю».
  void _autoSetReadingStatus() {
    ref
        .read(readingStatusProvider(widget.fileId).notifier)
        .autoSetReadingIfAbsent();
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
    _hintTimer?.cancel();
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    super.dispose();
  }

  void _toggleAppBar() {
    setState(() {
      _appBarVisible = !_appBarVisible;
      // Первое скрытие панели — подсказываем, как вернуть её обратно.
      if (!_appBarVisible && !_hintShown) {
        _hintShown = true;
        _hintVisible = true;
        _hintTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _hintVisible = false);
        });
      }
    });
  }

  Future<void> _saveProgress() async {
    if (_saving) return;
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) return;
    _saving = true;
    try {
      // Сохраняем на сервер
      await _actions.saveProgress(widget.fileId, pos);
    } catch (_) {}
    // Сохраняем локально в SQLite каталог. await обязателен: без него ошибка
    // записи SQLite улетала мимо try/catch как unhandled async error.
    try {
      final progress = _computeProgress(pos);
      await _offlineCatalog.updateProgress(widget.fileId, progress, pos);
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

  /// Панель ридера живёт в теме СТРАНИЦЫ, а не приложения: на сепии — тёплое
  /// стекло, в PDF/ночном — тёмное. Иначе светлая шапка «разрезала» бы
  /// тёмную страницу.
  ({Color tint, Color ink, Color ink2, Color line}) _chrome(BuildContext ctx) {
    if (widget.isPdf) {
      // PDF читается на тёмном полотне — панель тоже тёмная (как в дизайне).
      return (
        tint: const Color(0xFF1E1B18).withValues(alpha: 0.72),
        ink: SeeUColors.darkInk,
        ink2: SeeUColors.darkInk2,
        line: Colors.white.withValues(alpha: 0.08),
      );
    }

    final theme = ref.watch(readerSettingsProvider).theme;
    switch (theme) {
      case ReaderTheme.sepia:
        return (
          tint: const Color(0xFFF5EDD3).withValues(alpha: 0.86),
          ink: const Color(0xFF3D2B1A),
          ink2: const Color(0xFF8B6A47),
          line: const Color(0xFFD9CBA6),
        );
      case ReaderTheme.dark:
      case ReaderTheme.amoled:
        return (
          tint: (theme == ReaderTheme.amoled
                  ? Colors.black
                  : const Color(0xFF1A1A1A))
              .withValues(alpha: 0.82),
          ink: SeeUColors.darkInk,
          ink2: SeeUColors.darkInk2,
          line: Colors.white.withValues(alpha: 0.08),
        );
      case ReaderTheme.light:
        return (
          tint: const Color(0xFFFBFAF8).withValues(alpha: 0.82),
          ink: SeeUColors.textPrimary,
          ink2: SeeUColors.textSecondary,
          line: SeeUColors.borderSubtle,
        );
    }
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
              // Пилюля «тап — показать панель» — по центру снизу, при первом
              // скрытии панели, сама гаснет через 2.5 с.
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 28,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hintVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Center(child: _buildPanelHint(context)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Пилюля-подсказка в тоне текущей «страницы» (см. [_chrome]).
  Widget _buildPanelHint(BuildContext context) {
    final ch = _chrome(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: ch.ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'тап — показать панель',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: ch.ink2,
        ),
      ),
    );
  }

  /// Матовая шапка ридера поверх страницы: реальный BackdropFilter, кикер
  /// формата, серифное название, действия, коралловая нить прогресса и
  /// «осталось ~N».
  Widget _buildGlassBar(BuildContext context, SeeUThemeColors c, double topPad,
      double progress, Map<String, dynamic> pos) {
    final label = _progressLabel(pos);
    final ch = _chrome(context);
    // Текстовый ридер перетекает — так и подписываем; PDF — фиксированная вёрстка.
    final kicker = widget.isPdf
        ? widget.docFormat.toUpperCase()
        : '${widget.docFormat.toUpperCase()} · РЕФЛОУ';

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: ch.tint,
            border: Border(bottom: BorderSide(color: ch.line, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: topPad),
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.arrowLeft,
                          color: ch.ink, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            kicker,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: widget.isPdf
                                  ? LibColors.kickerDark
                                  : LibColors.kicker(context),
                            ),
                          ),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.displayS.copyWith(
                              fontSize: 18,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: ch.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.shareNetwork,
                          size: 19, color: ch.ink2),
                      tooltip: 'Поделиться',
                      onPressed: () => Share.share(
                        'Читаю «${widget.title}» в SeeU\n'
                        'seeu://files/${widget.fileId}',
                        subject: widget.title,
                      ),
                    ),
                    // Настройки — единственная «активная» кнопка в панели.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tappable.scaled(
                        onTap: () => showSeeUBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => widget.isPdf
                              ? PdfReaderSettingsSheet(
                                  currentPage:
                                      (pos['page'] as num?)?.toInt() ?? 0,
                                  totalPages:
                                      (pos['total'] as num?)?.toInt() ??
                                          widget.totalPages,
                                  onGoToPage: widget.onGoToPage,
                                )
                              : const ReaderSettingsSheet(),
                        ),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            widget.isPdf
                                ? PhosphorIconsFill.gear
                                : PhosphorIconsRegular.textAa,
                            size: 19,
                            color: widget.isPdf
                                ? LibColors.kickerDark
                                : SeeUColors.accent,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsRegular.bookmarkSimple,
                          size: 19, color: ch.ink2),
                      onPressed: () => _addBookmark(context),
                    ),
                  ],
                ),
              ),
              // Нить прогресса: коралл на бледно-коралловой дорожке.
              Container(
                height: 2,
                color: SeeUColors.accent.withValues(alpha: 0.15),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(color: SeeUColors.accent),
                ),
              ),
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12, color: ch.ink2),
                    ),
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
