import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_settings.dart';
import 'reader_shell.dart';

/// Ридер для TXT и MD форматов.
/// Скачивает оригинальный файл напрямую с R2 (fileUrl).
/// MD рендерится через flutter_markdown, TXT — SelectableText.
/// Поддерживает UTF-8 и Windows-1251 (кириллица CIS-локали).
/// Настройки (размер шрифта, тема) — из readerSettingsProvider.
/// Офлайн кэш: `<appDocDir>/<fileId>_text.txt`
class TextReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format; // 'txt' | 'md'
  final String fileUrl; // R2 публичный URL оригинального файла

  const TextReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
    required this.fileUrl,
  });

  @override
  ConsumerState<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends ConsumerState<TextReaderScreen> {
  String? _text;
  String? _error;
  final _scrollCtrl = ScrollController();
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
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

  Future<File?> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${widget.fileId}_text.txt');
  }

  Future<void> _init() async {
    final dio = ref.read(libraryApiClientProvider);
    // Загружаем прогресс параллельно, jumpTo делаем ПОСЛЕ рендера текста.
    final progressFuture = loadProgress(dio, widget.fileId);
    await _loadText();
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

  Future<void> _loadText() async {
    // Проверяем кэш
    final cache = await _cacheFile();
    if (cache != null && await cache.exists()) {
      final cached = await cache.readAsString();
      if (mounted) setState(() => _text = cached);
      return;
    }

    try {
      // Скачиваем оригинальный файл напрямую с R2
      final tmpDir = await getTemporaryDirectory();
      final tmpFile =
          File('${tmpDir.path}/${widget.fileId}_orig.${widget.format}');
      final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 3)));
      await dio.download(widget.fileUrl, tmpFile.path);

      final bytes = await tmpFile.readAsBytes();
      final text = _decodeText(bytes);

      if (mounted) setState(() => _text = text);

      // Кэшируем декодированный текст
      if (cache != null && text.isNotEmpty) {
        await cache.writeAsString(text);
      }
      // Удаляем временный файл
      if (await tmpFile.exists()) await tmpFile.delete();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
  }

  @override
  void dispose() {
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
      child: ColoredBox(
        color: bgColor,
        child: _buildContent(settings, textColor),
      ),
    );
  }

  Widget _buildContent(ReaderSettings settings, Color textColor) {
    final c = context.seeuColors;
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить файл', style: SeeUTypography.subtitle),
            const SizedBox(height: 6),
            Text(_error!,
                textAlign: TextAlign.center,
                style: SeeUTypography.caption.copyWith(color: c.ink3)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _loadText();
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_text == null) return const Center(child: CircularProgressIndicator());

    if (_text!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.fileText(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Файл пустой',
                style: SeeUTypography.body.copyWith(color: c.ink3)),
          ],
        ),
      );
    }

    if (widget.format == 'md') {
      return Markdown(
        controller: _scrollCtrl,
        data: _text!,
        padding: const EdgeInsets.all(20),
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: textColor),
          h1: TextStyle(
              fontSize: settings.fontSize + 8,
              fontWeight: FontWeight.w700,
              color: textColor),
          h2: TextStyle(
              fontSize: settings.fontSize + 4,
              fontWeight: FontWeight.w600,
              color: textColor),
          code: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: settings.fontSize - 2,
              color: SeeUColors.accent),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        _text!,
        style: TextStyle(
            fontSize: settings.fontSize,
            height: settings.lineHeight,
            color: textColor),
      ),
    );
  }
}
