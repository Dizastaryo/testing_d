import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';
import 'pdf_reader_screen.dart';

/// Промежуточный экран для форматов, конвертируемых в PDF на бэкенде:
/// fb2, docx, rtf, odt, pptx, odp.
///
/// Алгоритм:
///  1. GET /files/:id/pdf
///     - 200 → pdf_url готов, переходим на PdfReaderScreen
///     - 202 → конвертация в очереди, начинаем опрос /pdf-status каждые 3 с
///  2. Когда статус = done → повторяем GET /pdf → открываем ридер
///  3. Когда статус = failed → показываем ошибку
class ConvertedPdfReaderScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String format;

  const ConvertedPdfReaderScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.format,
  });

  @override
  ConsumerState<ConvertedPdfReaderScreen> createState() =>
      _ConvertedPdfReaderScreenState();
}

class _ConvertedPdfReaderScreenState
    extends ConsumerState<ConvertedPdfReaderScreen> {
  String? _error;
  bool _isPolling = false; // true while waiting for background conversion
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;
  int _pollAttempts = 0;
  // Poll every 3s; cap at 100 attempts (~5 min) so a stuck conversion can't
  // loop forever.
  static const _maxPollAttempts = 100;

  @override
  void initState() {
    super.initState();
    _fetchPdfUrl();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  String get _elapsedLabel {
    if (_elapsedSeconds < 60) return '$_elapsedSeconds сек.';
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '$m мин. $s сек.';
  }

  /// Ожидаемое время конвертации по формату.
  String _etaLabel(String format) {
    return switch (format) {
      'pptx' || 'odp' => '~60–120 сек.',
      'docx' || 'odt' => '~30–90 сек.',
      'fb2' => '~15–40 сек.',
      _ => '~15–60 сек.',
    };
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchPdfUrl() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _isPolling = false;
    });
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.filePdf(widget.fileId));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final pdfUrl = resp.data?['data']?['pdf_url'] as String?;
        if (pdfUrl == null || pdfUrl.isEmpty) {
          setState(() => _error = 'Сервер вернул пустой URL PDF');
          return;
        }
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            fileId: widget.fileId,
            title: widget.title,
            fileUrl: pdfUrl,
            originalFormat: widget.format,
          ),
        ));
      } else if (resp.statusCode == 202) {
        // Background conversion in progress — start polling
        _pollAttempts = 0;
        setState(() => _isPolling = true);
        _startElapsedTimer();
        _pollStatus();
      } else {
        final msg = resp.data?['error'] as String? ?? 'Ошибка ${resp.statusCode}';
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pollStatus() async {
    final dio = ref.read(libraryApiClientProvider);
    while (mounted && _isPolling && _error == null) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      if (++_pollAttempts > _maxPollAttempts) {
        _elapsedTimer?.cancel();
        if (mounted) {
          setState(() {
            _isPolling = false;
            _error = 'Конвертация заняла слишком много времени. Попробуйте позже.';
          });
        }
        return;
      }
      try {
        final resp = await dio.get(ApiEndpoints.filePdfStatus(widget.fileId));
        // Экран могли закрыть, пока летел запрос статуса — без guard'а setState
        // и _fetchPdfUrl падали «called after dispose» (ветка failed ниже
        // guard уже имела, а done — нет).
        if (!mounted) return;
        final status = resp.data?['data']?['status'] as String? ?? 'pending';
        if (status == 'done') {
          // Ready — fetch the actual PDF URL
          _elapsedTimer?.cancel();
          setState(() => _isPolling = false);
          _fetchPdfUrl();
          return;
        } else if (status == 'failed') {
          _elapsedTimer?.cancel();
          if (mounted) {
            setState(() {
              _isPolling = false;
              _error = 'Конвертация не удалась. Попробуйте позже.';
            });
          }
          return;
        }
        // status = pending | converting — keep polling
      } catch (_) {
        // network glitch — keep polling
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: topPad + kToolbarHeight),
              child: _error != null ? _buildError() : _buildLoading(c),
            ),
          ),
          // Матовая шапка поверх контента — рецепт reader_shell:
          // реальный BackdropFilter + surface α0.72 + hairline.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildGlassBar(c, topPad),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBar(SeeUThemeColors c, double topPad) {
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
                            'КОНВЕРТАЦИЯ',
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
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(SeeUThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: SeeUColors.accent,
                backgroundColor: SeeUColors.accent.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isPolling ? 'Конвертация документа...' : 'Подготовка к чтению...',
              style: SeeUTypography.body.copyWith(color: c.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    border: Border.all(
                        color: SeeUColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    widget.format.toUpperCase(),
                    style: TextStyle(
                      fontFamily: AppFonts.I.sans,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SeeUColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '→ PDF',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.ink3,
                    fontFamily: AppFonts.I.sans,
                  ),
                ),
              ],
            ),
            if (_isPolling) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                  border: Border.all(color: c.line),
                  boxShadow: SeeUShadows.sm,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.timer,
                            size: 14, color: c.ink3),
                        const SizedBox(width: 6),
                        Text(
                          'Прошло: $_elapsedLabel',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.ink3,
                            fontFamily: AppFonts.I.sans,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ожидаемое время: ${_etaLabel(widget.format)}',
                      style: TextStyle(fontSize: 11, color: c.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Можно закрыть и вернуться позже',
                style: TextStyle(fontSize: 12, color: c.ink4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(PhosphorIconsRegular.x,
                    size: 14, color: c.ink3),
                label: Text('Закрыть',
                    style: TextStyle(color: c.ink3)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return SeeUErrorState(
      error: _error,
      title: 'Не удалось открыть документ',
      onRetry: () {
        setState(() => _error = null);
        _fetchPdfUrl();
      },
    );
  }
}
