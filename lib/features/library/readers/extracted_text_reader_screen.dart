import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_shell.dart';

/// Ридер для Tier 2 форматов (FB2, DOCX, RTF, ODT).
/// Показывает extracted_text с дисклеймером о потере форматирования.
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
  double _fontSize = 16.0;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _init() async {
    final dio = ref.read(libraryApiClientProvider);
    await Future.wait([_loadText(dio), _restoreProgress(dio)]);
  }

  Future<void> _loadText(Dio dio) async {
    try {
      final resp = await dio.get(ApiEndpoints.fileText(widget.fileId));
      if (resp.statusCode == 204) {
        if (mounted) setState(() => _text = '');
        return;
      }
      final text = resp.data?['data']?['text'] as String? ?? '';
      if (mounted) setState(() => _text = text);
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
    final c = context.seeuColors;
    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: widget.format,
      positionNotifier: _positionNotifier,
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
                    'Форматирование может быть потеряно. '
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
          // Font size controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: c.surface,
            child: Row(
              children: [
                const Text('Aa', style: TextStyle(fontSize: 12)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.text_decrease, size: 18),
                  onPressed: () =>
                      setState(() => _fontSize = (_fontSize - 1).clamp(12.0, 28.0)),
                ),
                Text('${_fontSize.toInt()}',
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 12)),
                IconButton(
                  icon: const Icon(Icons.text_increase, size: 18),
                  onPressed: () =>
                      setState(() => _fontSize = (_fontSize + 1).clamp(12.0, 28.0)),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent(c)),
        ],
      ),
    );
  }

  Widget _buildContent(SeeUThemeColors c) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить текст', style: SeeUTypography.subtitle),
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
        style: TextStyle(fontSize: _fontSize, height: 1.7, color: c.ink),
      ),
    );
  }
}
