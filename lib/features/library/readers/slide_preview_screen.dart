import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'reader_shell.dart';

class _Slide {
  final int index;
  final String text;
  const _Slide({required this.index, required this.text});
}

/// Предпросмотр слайдов для PPTX/ODP.
/// Бэкенд возвращает текст в формате "[Слайд N]\n...текст...\n\n".
/// Парсим это и показываем как карусель слайдов.
class SlidePreviewScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format;
  final String fileUrl;

  const SlidePreviewScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
    required this.fileUrl,
  });

  @override
  ConsumerState<SlidePreviewScreen> createState() => _SlidePreviewScreenState();
}

class _SlidePreviewScreenState extends ConsumerState<SlidePreviewScreen> {
  List<_Slide>? _slides;
  String? _error;
  int _currentPage = 0;
  final _pageCtrl = PageController();
  final _positionNotifier = ValueNotifier<Map<String, dynamic>>({});

  @override
  void initState() {
    super.initState();
    _loadSlides();
  }

  Future<void> _loadSlides() async {
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.fileText(widget.fileId));
      if (resp.statusCode == 204 || resp.data == null) {
        if (mounted) setState(() => _slides = []);
        return;
      }

      final rawText = resp.data?['data']?['text'] as String? ?? '';
      if (mounted) setState(() => _slides = _parseSlides(rawText));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<_Slide> _parseSlides(String text) {
    // Формат: "[Слайд N]\nтекст\n\n"
    final slides = <_Slide>[];
    final slidePattern = RegExp(r'\[Слайд (\d+)\]\n([\s\S]*?)(?=\[Слайд \d+\]|$)');
    for (final match in slidePattern.allMatches(text)) {
      final idx = int.tryParse(match.group(1) ?? '0') ?? 0;
      final content = (match.group(2) ?? '').trim();
      slides.add(_Slide(index: idx, text: content));
    }
    // Fallback: если не распарсилось, показываем весь текст как один слайд
    if (slides.isEmpty && text.isNotEmpty) {
      slides.add(_Slide(index: 1, text: text));
    }
    return slides;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderShell(
      fileId: widget.fileId,
      title: widget.title,
      docFormat: widget.format,
      positionNotifier: _positionNotifier,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final c = context.seeuColors;
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.warning(), size: 48, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить слайды', style: SeeUTypography.subtitle),
          ],
        ),
      );
    }
    if (_slides == null) return const Center(child: CircularProgressIndicator());
    if (_slides!.isEmpty) {
      return Center(
        child: Text('Текст слайдов не доступен',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      );
    }

    return Column(
      children: [
        // Slide counter
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: c.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Слайд ${_currentPage + 1} / ${_slides!.length}',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    color: c.ink2),
              ),
            ],
          ),
        ),

        // Slides carousel
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _slides!.length,
            itemBuilder: (ctx, i) => _buildSlide(_slides![i], c),
          ),
        ),

        // Download CTA
        Container(
          padding: const EdgeInsets.all(16),
          color: c.surface,
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.info, size: 14, color: c.ink3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Скачайте оригинал для просмотра в полном качестве',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(widget.fileUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Скачать',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSlide(_Slide slide, SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Slide header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: SeeUColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'Слайд ${slide.index}',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: SeeUColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            // Slide content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  slide.text.isEmpty ? '(Слайд без текста)' : slide.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
