import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/offline_catalog_provider.dart';
import '../../../core/services/offline_storage_service.dart';
import '../../../core/services/reading_tracker.dart';
import 'reader_settings.dart';
import 'reader_shell.dart';

/// Ридер для TXT и MD форматов.
/// Скачивает оригинальный файл напрямую с R2 (fileUrl).
/// MD рендерится через flutter_markdown, TXT — SelectableText.
/// Поддерживает UTF-8 и Windows-1251 (кириллица CIS-локали).
/// Настройки (размер шрифта, тема) — из readerSettingsProvider.
class TextReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format; // 'txt' | 'md'
  final String fileUrl; // R2 публичный URL оригинального файла
  final String? author;
  final String? coverUrl;
  final bool isBook;

  const TextReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
    required this.fileUrl,
    this.author,
    this.coverUrl,
    this.isBook = false,
  });

  @override
  ConsumerState<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends ConsumerState<TextReaderScreen> {
  String? _text;
  String? _error;

  /// Document split into bounded chunks for lazy, memory-safe rendering.
  List<String>? _chunks;
  final _scrollCtrl = ScrollController();
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});
  ReadingTracker? _tracker;
  int _lastVirtualPage = -1;

  /// In-memory cap: above this we never lay the whole doc out at once and we
  /// never feed it to the (eager) Markdown widget.
  static const _maxInlineChars = 2 * 1024 * 1024; // ~2 MB of text

  /// Stable "virtual page" size in characters (independent of font/viewport).
  static const _charsPerPage = 1800;

  /// Max characters per rendered chunk (bounds a single SelectableText).
  static const _maxChunkChars = 4000;

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
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _init() async {
    final progressFuture = ref.read(libraryActionsProvider).loadProgress(widget.fileId);
    final futures = <Future>[_loadText()];
    if (_tracker != null) futures.add(_tracker!.init());
    await Future.wait(futures);
    final progress = await progressFuture;
    if (progress == null || !mounted) return;
    final offset = (progress['offset'] as num?)?.toDouble() ?? 0;
    if (offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(
            offset.clamp(0, _scrollCtrl.position.maxScrollExtent),
          );
        }
      });
    }
  }

  /// Computes a virtual page number from the scroll position.
  ///
  /// Uses a *stable* unit — a character-offset bucket derived from how far
  /// through the document we are scrolled — so the page number does not jump
  /// when the font size or orientation (and therefore the pixel height of the
  /// content) changes.
  int _virtualPage() {
    if (!_scrollCtrl.hasClients || _text == null) return 0;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return 0;
    final fraction = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    final charOffset = (fraction * _text!.length).floor();
    return charOffset ~/ _charsPerPage;
  }

  /// Splits text into bounded chunks (paragraphs, capped at [_maxChunkChars])
  /// so a `ListView.builder` only ever lays out the visible ones.
  List<String> _splitIntoChunks(String text) {
    final paragraphs = text.split(RegExp(r'\n[ \t]*\n'));
    final result = <String>[];
    for (final para in paragraphs) {
      if (para.length <= _maxChunkChars) {
        result.add(para);
      } else {
        for (var i = 0; i < para.length; i += _maxChunkChars) {
          final end =
              (i + _maxChunkChars) < para.length ? i + _maxChunkChars : para.length;
          result.add(para.substring(i, end));
        }
      }
    }
    return result;
  }

  Future<void> _loadText() async {
    final service = ref.read(offlineStorageProvider);
    final cached = await service.readText(widget.fileId);
    if (cached != null) {
      if (mounted) setState(() { _text = cached; _chunks = null; });
      return;
    }

    try {
      // Скачиваем через offlineCatalogProvider (автоматически сохраняет в каталог)
      final repo = ref.read(offlineCatalogProvider);
      final path = await repo.ensureAvailable(
        widget.fileId,
        OfflineKind.text,
        widget.fileUrl,
        title: widget.title,
        author: widget.author,
        coverUrl: widget.coverUrl,
        originalFormat: widget.format,
      );

      final bytes = await File(path).readAsBytes();
      final text = _decodeText(bytes);

      if (mounted) setState(() { _text = text; _chunks = null; });

      // Кэшируем декодированный текст для быстрого доступа
      if (text.isNotEmpty) {
        await service.saveText(widget.fileId, text);
      }
    } catch (e) {
      if (mounted) {
        final s = e.toString();
        if (s.contains('DatabaseException')) {
          setState(() => _error = 'Ошибка локальной базы данных. Попробуйте перезапустить приложение.');
        } else if (s.contains('SocketException') || s.contains('Connection refused')) {
          setState(() => _error = 'Нет подключения к серверу');
        } else {
          setState(() => _error = s);
        }
      }
    }
  }

  /// Декодирует байты в строку.
  /// Порядок: BOM UTF-8 → UTF-8 → Windows-1251 (CIS Cyrillic fallback).
  String _decodeText(Uint8List bytes) {
    // BOM UTF-8: EF BB BF
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: false);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return _decodeWindows1251(bytes);
    }
  }

  /// Декодирует Windows-1251 байты в Unicode.
  /// Таблица соответствий для диапазона 0x80–0xFF.
  String _decodeWindows1251(Uint8List bytes) {
    const cp1251 = <int>[
      0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
      0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
      0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x0000, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
      0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
      0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
      0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
      0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
      0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
      0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
      0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
      0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
      0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
      0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
      0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
      0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
    ];
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else {
        final cp = cp1251[b - 0x80];
        buf.writeCharCode(cp != 0 ? cp : 0xFFFD);
      }
    }
    return buf.toString();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    _positionNotifier.value = {
      'offset': _scrollCtrl.offset,
      'total': _scrollCtrl.position.maxScrollExtent,
    };
    // Track virtual page for reading timer
    final vp = _virtualPage();
    if (vp != _lastVirtualPage) {
      _lastVirtualPage = vp;
      _tracker?.startPage(vp);
    }
  }

  @override
  void dispose() {
    _tracker?.dispose();
    _scrollCtrl.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final bgColor = settings.backgroundColor(context);
    final textColor = settings.textColor(context);

    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: widget.format,
      positionNotifier: _positionNotifier,
      child: Stack(
        children: [
          ColoredBox(
            color: bgColor,
            child: _buildContent(settings, textColor),
          ),
          // Reading progress bar at bottom (books only)
          if (_tracker != null)
            Positioned(
              bottom: 8,
              left: 24,
              right: 24,
              child: _TextReadingBar(
                tracker: _tracker!,
                isDark: settings.isNightMode,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ReaderSettings settings, Color textColor) {
    if (_error != null) {
      return SeeUErrorState(
        error: _error,
        title: 'Не удалось загрузить файл',
        onRetry: () {
          setState(() => _error = null);
          _loadText();
        },
      );
    }

    if (_text == null) {
      return const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      );
    }

    if (_text!.isEmpty) {
      return const SeeUEmptyState(
        icon: PhosphorIconsRegular.fileText,
        title: 'Файл пустой',
      );
    }

    final tooLarge = _text!.length > _maxInlineChars;

    // Markdown is rendered eagerly (lays the whole doc out at once), so only
    // use it for small .md files. Large docs fall back to the chunked plain
    // view below — which never lays out more than the visible chunks.
    if (widget.format == 'md' && !tooLarge) {
      return Markdown(
        controller: _scrollCtrl,
        data: _text!,
        padding: const EdgeInsets.all(20),
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
              fontFamily: settings.fontFamilyName,
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: textColor),
          // Editorial-иерархия заголовков: сериф Fraunces вместо reader-шрифта.
          // Размер зависит от reader-настройки, поэтому не токен — но добавляем
          // кириллический fallback (Playfair), иначе русские заголовки теряют
          // сериф (у Fraunces нет кириллицы).
          h1: TextStyle(
              fontFamily: 'Fraunces',
              fontFamilyFallback: const ['Playfair Display'],
              fontSize: settings.fontSize + 12,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
              height: 1.15,
              color: textColor),
          h2: TextStyle(
              fontFamily: 'Fraunces',
              fontFamilyFallback: const ['Playfair Display'],
              fontSize: settings.fontSize + 7,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
              height: 1.2,
              color: textColor),
          h3: TextStyle(
              fontFamily: 'Fraunces',
              fontFamilyFallback: const ['Playfair Display'],
              fontSize: settings.fontSize + 3,
              fontWeight: FontWeight.w600,
              color: textColor),
          code: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: settings.fontSize - 2,
              color: SeeUColors.accent),
          a: const TextStyle(
              color: SeeUColors.accent,
              decoration: TextDecoration.underline,
              decorationColor: SeeUColors.accent),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: SeeUColors.accent.withValues(alpha: 0.5), width: 3),
            ),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
        ),
      );
    }

    // Lazy, size-bounded rendering: split the document into chunks and let
    // ListView.builder lay out only the visible ones. Each chunk gets its own
    // SelectableText so we never build a single giant text layout (OOM source).
    final chunks = _chunks ??= _splitIntoChunks(_text!);
    final textStyle = TextStyle(
        fontFamily: settings.fontFamilyName,
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: textColor);
    final showBanner = tooLarge;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: chunks.length + (showBanner ? 1 : 0),
      itemBuilder: (context, index) {
        if (showBanner && index == 0) {
          return _buildTooLargeBanner();
        }
        final i = showBanner ? index - 1 : index;
        final chunk = chunks[i];
        if (chunk.trim().isEmpty) {
          return SizedBox(height: settings.fontSize);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText(chunk, style: textStyle),
        );
      },
    );
  }

  Widget _buildTooLargeBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeeUColors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: SeeUColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.warning,
              size: 18, color: SeeUColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Файл слишком большой — для точного форматирования скачайте оригинал',
              style: SeeUTypography.caption.copyWith(color: SeeUColors.warning),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(widget.fileUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              'Скачать',
              style: SeeUTypography.caption.copyWith(
                color: SeeUColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Text Reading Progress Bar ──────────────────────────────────────────────

class _TextReadingBar extends StatelessWidget {
  final ReadingTracker tracker;

  /// true для тёмных тем чтения (dark/AMOLED) — трек светлее фона;
  /// на светлых (light/sepia) — тонкий c.line.
  final bool isDark;
  const _TextReadingBar({required this.tracker, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : context.seeuColors.line;
    return ValueListenableBuilder<double>(
      valueListenable: tracker.currentPageProgress,
      builder: (_, progress, __) => ValueListenableBuilder<bool>(
        valueListenable: tracker.currentPageRead,
        builder: (_, isRead, __) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: trackColor,
            ),
            clipBehavior: Clip.antiAlias,
            child: FractionallySizedBox(
              widthFactor: progress,
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isRead
                      ? SeeUColors.success
                      : SeeUColors.accent.withValues(alpha: 0.85),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
