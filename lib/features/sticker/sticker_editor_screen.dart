import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';
import 'providers/sticker_editor_provider.dart';
import 'sticker_done_screen.dart';
import 'widgets/editor_bottom_bar.dart';
import 'widgets/sticker_canvas.dart';

class StickerEditorScreen extends ConsumerStatefulWidget {
  /// URL изображения с удалённым фоном (относительный или абсолютный).
  final String imageUrl;

  const StickerEditorScreen({super.key, required this.imageUrl});

  @override
  ConsumerState<StickerEditorScreen> createState() =>
      _StickerEditorScreenState();
}

class _StickerEditorScreenState extends ConsumerState<StickerEditorScreen> {
  final _boundaryKey = GlobalKey();
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();

  bool _saving = false;

  /// Флаг: не обрабатывать изменения контроллера пока синхронизируем из провайдера.
  bool _syncingFromProvider = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Синхронизация текста ───────────────────────────────────────

  void _onTextChanged() {
    if (_syncingFromProvider) return;
    ref.read(stickerEditorProvider.notifier).setActiveLayerText(_textCtrl.text);
  }

  void _onFocusChanged() {
    // При потере фокуса фиксируем изменения в историю.
    if (!_focusNode.hasFocus) {
      ref.read(stickerEditorProvider.notifier).commitGesture();
    }
  }

  void _syncControllerFromState(StickerEditorState state) {
    final text = state.activeLayer?.text ?? '';
    if (_textCtrl.text == text) return;
    _syncingFromProvider = true;
    _textCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingFromProvider = false;
  }

  // ── Сохранение ────────────────────────────────────────────────

  Future<void> _save() async {
    // Скрываем клавиатуру и снимаем активный слой перед рендером.
    _focusNode.unfocus();
    ref.read(stickerEditorProvider.notifier).setActive(null);

    // Даём Flutter завершить rebuild без selection handles.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Не удалось рендерить стикер');

      final pngBytes = byteData.buffer.asUint8List();
      final sticker =
          await ref.read(stickerListProvider.notifier).saveSticker(pngBytes);

      if (!mounted) return;
      setState(() => _saving = false);

      // Показываем экран «Стикер готов» и ждём подтверждения.
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => StickerDoneScreen(imageUrl: sticker.url),
        ),
      );

      if (confirmed == true && mounted) {
        Navigator.of(context).pop(sticker.url);
      }
    } catch (e) {
      if (mounted) {
        showSeeUSnackBar(context, 'Ошибка сохранения: $e',
            tone: SeeUTone.danger);
        setState(() => _saving = false);
      }
    }
  }

  // ── Закрытие ──────────────────────────────────────────────────

  Future<void> _onClose() async {
    if (_saving) return;
    final hasChanges = ref.read(stickerEditorProvider).layers.isNotEmpty;

    if (!hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    final confirmed = await showSeeUConfirm(
      context,
      title: 'Выйти без сохранения?',
      message: 'Изменения будут потеряны.',
      confirmLabel: 'Выйти',
      destructive: true,
      icon: PhosphorIconsRegular.signOut,
    );

    if (confirmed && mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Слушаем изменения провайдера для синхронизации контроллера и фокуса.
    ref.listen<StickerEditorState>(stickerEditorProvider, (prev, next) {
      _syncControllerFromState(next);

      // Слой только что стал активным → открываем клавиатуру.
      if (next.activeLayerId != null &&
          prev?.activeLayerId != next.activeLayerId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }

      // Слой снят → закрываем клавиатуру.
      if (next.activeLayerId == null && prev?.activeLayerId != null) {
        _focusNode.unfocus();
      }
    });

    final c = context.seeuColors;
    final state = ref.watch(stickerEditorProvider);
    final activeLayer = state.activeLayer;
    final absUrl = AppConfig.absUrl(widget.imageUrl);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _onClose();
      },
      child: Scaffold(
        backgroundColor: c.surface2,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              // ── Шапка ────────────────────────────────────────────
              _buildHeader(c, state),
              Divider(height: 1, color: c.line),

              // ── Холст (занимает всё свободное пространство) ──────
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Boundary indicator shadow/glow
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: SeeUColors.accent.withValues(alpha: 0.18),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          // Actual sticker canvas
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: StickerCanvas(
                                backgroundImage: NetworkImage(absUrl),
                                onEditText: (_) => _focusNode.requestFocus(),
                              ),
                            ),
                          ),
                          // Dashed boundary frame on top
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _BoundaryPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Поле ввода (видно только при активном слое) ───────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: activeLayer != null
                    ? _TextInputRow(
                        controller: _textCtrl,
                        focusNode: _focusNode,
                        onDone: () {
                          _focusNode.unfocus();
                          ref.read(stickerEditorProvider.notifier)
                            ..commitGesture()
                            ..setActive(null);
                        },
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Нижняя панель инструментов ────────────────────────
              EditorBottomBar(
                onAddText: ref.read(stickerEditorProvider.notifier).addLayer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c, StickerEditorState state) {
    final notifier = ref.read(stickerEditorProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          // X — закрыть
          GestureDetector(
            onTap: _saving ? null : _onClose,
            child: Icon(PhosphorIcons.x(), size: 20, color: _saving ? c.ink4 : c.ink),
          ),
          const Spacer(),
          // Undo / Redo
          Row(
            children: [
              GestureDetector(
                onTap: notifier.canUndo ? notifier.undo : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Icon(
                    PhosphorIconsRegular.arrowCounterClockwise,
                    size: 22,
                    color: notifier.canUndo ? c.ink2 : c.ink4,
                  ),
                ),
              ),
              GestureDetector(
                onTap: notifier.canRedo ? notifier.redo : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Icon(
                    PhosphorIconsRegular.arrowClockwise,
                    size: 22,
                    color: notifier.canRedo ? c.ink2 : c.ink4,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Готово
          if (_saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: _save,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Center(
                  child: Text(
                    'Готово',
                    style: SeeUTypography.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Поле ввода текста текущего слоя ─────────────────────────────

class _TextInputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDone;

  const _TextInputRow({
    required this.controller,
    required this.focusNode,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // Стеклянная панель ввода: blur 26 + surface α0.8 + верхний hairline.
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.8),
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: SeeUTypography.body.copyWith(color: c.ink, fontSize: 16),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onDone(),
                decoration: InputDecoration(
                  hintText: 'Введите текст…',
                  hintStyle: SeeUTypography.body.copyWith(
                    color: c.ink4,
                    fontSize: 16,
                  ),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: onDone,
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Text(
                  'Готово',
                  style: SeeUTypography.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sticker boundary dashed painter ─────────────────────────────

class _BoundaryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(16);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final paint = Paint()
      ..color = SeeUColors.accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw dashed rounded rectangle
    const dashLen = 6.0;
    const gapLen = 5.0;
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();

    for (final metric in metrics) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final step = draw ? dashLen : gapLen;
        final end = math.min(distance + step, metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(distance, end), paint);
        }
        distance = end;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
