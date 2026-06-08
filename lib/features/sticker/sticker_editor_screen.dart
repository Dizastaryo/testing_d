import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';
import 'providers/sticker_editor_provider.dart';
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

      if (mounted) Navigator.of(context).pop(sticker.url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти без сохранения?'),
        content: const Text('Изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Выйти',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) Navigator.of(context).pop();
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
        appBar: _buildAppBar(c, state),
        body: Column(
          children: [
            // ── Холст (занимает всё свободное пространство) ──────
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: StickerCanvas(
                        backgroundImage: NetworkImage(absUrl),
                        onEditText: (_) => _focusNode.requestFocus(),
                      ),
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
    );
  }

  PreferredSizeWidget _buildAppBar(SeeUThemeColors c, StickerEditorState state) {
    final notifier = ref.read(stickerEditorProvider.notifier);
    return AppBar(
      backgroundColor: c.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(PhosphorIconsRegular.x, color: c.ink),
        onPressed: _saving ? null : _onClose,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: notifier.canUndo ? notifier.undo : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(
                PhosphorIconsRegular.arrowClockwise,
                size: 22,
                color: notifier.canRedo ? c.ink2 : c.ink4,
              ),
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 9, 12, 9),
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
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
          ),
      ],
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
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onDone(),
                decoration: InputDecoration(
                  hintText: 'Введите текст...',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 16,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: onDone,
              child: Text(
                'Готово',
                style: TextStyle(
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
