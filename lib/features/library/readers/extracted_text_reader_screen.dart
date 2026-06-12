import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_settings.dart';
import 'reader_shell.dart';

/// Ридер для Tier 2 форматов (FB2, DOCX, RTF, ODT).
/// Показывает extracted_text с дисклеймером о потере форматирования.
/// Настройки из readerSettingsProvider. Офлайн кэш: `<appDocDir>/<fileId>_text.txt`
class ExtractedTextReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format;

  const ExtractedTextReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
  });

  @override
  ConsumerState<ExtractedTextReaderScreen> createState() =>
      _ExtractedTextReaderScreenState();
}

class _ExtractedTextReaderScreenState
    extends ConsumerState<ExtractedTextReaderScreen> {
  String? _text;
  String? _error;
  final _scrollCtrl = ScrollController();
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    _init();
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _init() async {
    final dio = ref.read(libraryApiClientProvider);
    await Future.wait([_loadText(), _restoreProgress(dio)]);
  }

  Future<File?> _cacheFile() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${widget.fileId}_text.txt');
  }

  Future<void> _loadText() async {
    final cache = await _cacheFile();
    if (cache != null && await cache.exists()) {
      final cached = await cache.readAsString();
      if (mounted) setState(() => _text = cached);
      return;
    }

    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.fileText(widget.fileId));
      if (resp.statusCode == 204) {
        if (mounted) setState(() => _text = '');
        return;
      }
      final text = resp.data?['data']?['text'] as String? ?? '';
      if (mounted) setState(() => _text = text);
      if (cache != null && text.isNotEmpty) {
        await cache.writeAsString(text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _restoreProgress(Dio dio) async {
    final progress = await loadProgress(dio, widget.fileId);
    if (progress == null || !mounted) return;
    final offset = (progress['offset'] as num?)?.toDouble() ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && offset > 0) {
        _scrollCtrl.jumpTo(
            offset.clamp(0, _scrollCtrl.position.maxScrollExtent));
      }
    });
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
        child: Column(
          children: [
            // Disclaimer banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: SeeUColors.accent.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.info,
                      size: 16, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Показан извлечённый текст (${widget.format.toUpperCase()}). '
                      'Скачайте оригинал для полного просмотра.',
                      style: TextStyle(
                          fontSize: 11,
                          color: SeeUColors.accent.withValues(alpha: 0.9),
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildContent(settings, textColor)),
          ],
        ),
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
            Text('Не удалось загрузить текст', style: SeeUTypography.subtitle),
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
        child: Text('Текст не был извлечён из файла',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
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
