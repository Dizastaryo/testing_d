import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
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

  const ReaderShell({
    super.key,
    required this.fileId,
    required this.title,
    required this.docFormat,
    required this.positionNotifier,
    required this.child,
  });

  @override
  ConsumerState<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<ReaderShell> {
  late final Dio _dio;
  bool _appBarVisible = true;

  @override
  void initState() {
    super.initState();
    _dio = ref.read(libraryApiClientProvider);
  }

  @override
  void dispose() {
    _saveProgress();
    super.dispose();
  }

  void _toggleAppBar() => setState(() => _appBarVisible = !_appBarVisible);

  Future<void> _saveProgress() async {
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) return;
    try {
      // Сохраняем на сервер
      await _dio.put(ApiEndpoints.fileProgress(widget.fileId), data: {'position': pos});
    } catch (_) {}
    // Сохраняем локально в SQLite каталог
    try {
      final progress = _computeProgress(pos);
      ref.read(offlineCatalogProvider).updateProgress(widget.fileId, progress, pos);
    } catch (_) {}
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
          return Column(
            children: [
              // ─── Кастомный AppBar (анимированно скрывается при тапе) ───────
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                height: _appBarVisible ? kToolbarHeight + topPad : 0,
                color: c.surface,
                clipBehavior: Clip.antiAlias,
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
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                Text(
                                  widget.docFormat.toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 10,
                                    color: SeeUColors.accent,
                                  ),
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
                            icon: Icon(PhosphorIconsRegular.textAa, color: c.ink2),
                            tooltip: 'Настройки',
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const ReaderSettingsSheet(),
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
                  ],
                ),
              ),

              // ─── Тонкий прогресс-бар ─────────────────────────────────────
              AnimatedOpacity(
                opacity: progress > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : 0,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    SeeUColors.accent.withValues(alpha: 0.55),
                  ),
                ),
              ),

              // ─── Контент ридера ───────────────────────────────────────────
              // Тап по контенту скрывает/показывает AppBar.
              // HitTestBehavior.translucent: оба (жест детектор + дочерние)
              // участвуют в hit-test. Для PDF свайп не конфликтует с onTap.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleAppBar,
                  child: widget.child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addBookmark(BuildContext context) async {
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Прокрутите немного, затем добавьте закладку'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      await _dio.post(
        ApiEndpoints.fileBookmarks(widget.fileId),
        data: {'position': pos, 'note': ''},
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Закладка добавлена')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить закладку')),
      );
    }
  }
}

/// Загружает текущий прогресс файла. Возвращает null если нет.
Future<Map<String, dynamic>?> loadProgress(Dio dio, String fileId) async {
  try {
    final resp = await dio.get(ApiEndpoints.fileProgress(fileId));
    if (resp.statusCode == 204) return null;
    final data = resp.data?['data'];
    if (data == null) return null;
    final pos = data['position'];
    if (pos is Map) return Map<String, dynamic>.from(pos);
    if (pos is String) {
      return Map<String, dynamic>.from(jsonDecode(pos) as Map);
    }
    return null;
  } catch (_) {
    return null;
  }
}
