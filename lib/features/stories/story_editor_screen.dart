import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';
import '../../core/models/story.dart';

/// Результат работы редактора: composite PNG-кадр + опционально interactive
/// poll (STORY-3). Если poll присутствует — он НЕ растеризован в кадр; viewer
/// рендерит интерактивные кнопки поверх media в позиции (x,y).
class StoryEditorResult {
  final Uint8List bytes;
  final StoryPoll? poll;
  const StoryEditorResult({required this.bytes, this.poll});
}

enum _BgStyle { none, blur, solid }
enum _TextAlign2 { left, center, right }

/// Полно-экранный редактор сторис: фото как фон + draggable текст/стикеры.
/// На «Готово» делает `RepaintBoundary.toImage()` → возвращает PNG-bytes +
/// (опционально) interactive poll через `Navigator.pop(StoryEditorResult)`.
class StoryEditorScreen extends StatefulWidget {
  final Uint8List initialBytes;

  const StoryEditorScreen({super.key, required this.initialBytes});

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final _canvasKey = GlobalKey();
  final List<_TextOverlay> _texts = [];
  final List<_StickerOverlay> _stickers = [];
  final List<_PollOverlay> _polls = [];
  final List<_QuestionOverlay> _questions = [];
  int _nextId = 1;
  bool _exporting = false;

  // ── Undo stack ──
  // Each entry is a snapshot of (texts, stickers, polls, questions) lists.
  final List<_HistorySnapshot> _undoStack = [];

  // ── Inline text editor state ──
  bool _isEditingText = false;
  int? _editingTextId; // null = creating new
  final _inlineTextCtrl = TextEditingController();
  Color _inlineColor = Colors.white;
  _BgStyle _inlineBgStyle = _BgStyle.none;
  Color _inlineBgColor = Colors.black;
  double _inlineFontSize = 28.0;
  _TextAlign2 _inlineAlign = _TextAlign2.center;
  final _inlineTextFocus = FocusNode();

  @override
  void dispose() {
    _inlineTextCtrl.dispose();
    _inlineTextFocus.dispose();
    super.dispose();
  }

  // ── History ──

  void _saveUndo() {
    _undoStack.add(_HistorySnapshot(
      texts: _texts.map((t) => t.copy()).toList(),
      stickers: _stickers.map((s) => s.copy()).toList(),
      polls: _polls.map((p) => p.copy()).toList(),
      questions: _questions.map((q) => q.copy()).toList(),
    ));
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    HapticFeedback.mediumImpact();
    final snap = _undoStack.removeLast();
    setState(() {
      _texts
        ..clear()
        ..addAll(snap.texts);
      _stickers
        ..clear()
        ..addAll(snap.stickers);
      _polls
        ..clear()
        ..addAll(snap.polls);
      _questions
        ..clear()
        ..addAll(snap.questions);
    });
  }

  // ── Text editor ──

  void _addText() {
    _inlineTextCtrl.clear();
    _inlineColor = Colors.white;
    _inlineBgStyle = _BgStyle.none;
    _inlineBgColor = Colors.black;
    _inlineFontSize = 28.0;
    _inlineAlign = _TextAlign2.center;
    _editingTextId = null;
    setState(() => _isEditingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineTextFocus.requestFocus();
    });
  }

  void _editText(_TextOverlay t) {
    _inlineTextCtrl.text = t.text;
    _inlineColor = t.color;
    _inlineBgStyle = t.bgStyle;
    _inlineBgColor = t.bgColor;
    _inlineFontSize = t.fontSize;
    _inlineAlign = t.align;
    _editingTextId = t.id;
    setState(() => _isEditingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineTextFocus.requestFocus();
    });
  }

  void _confirmInlineText() {
    final text = _inlineTextCtrl.text.trim();
    _inlineTextFocus.unfocus();
    if (text.isEmpty) {
      setState(() => _isEditingText = false);
      return;
    }
    _saveUndo();
    setState(() {
      _isEditingText = false;
      if (_editingTextId == null) {
        _texts.add(_TextOverlay(
          id: _nextId++,
          text: text,
          color: _inlineColor,
          bgStyle: _inlineBgStyle,
          bgColor: _inlineBgColor,
          fontSize: _inlineFontSize,
          align: _inlineAlign,
          position: const Offset(0.35, 0.42),
          scale: 1.0,
        ));
      } else {
        final idx = _texts.indexWhere((t) => t.id == _editingTextId);
        if (idx >= 0) {
          _texts[idx]
            ..text = text
            ..color = _inlineColor
            ..bgStyle = _inlineBgStyle
            ..bgColor = _inlineBgColor
            ..fontSize = _inlineFontSize
            ..align = _inlineAlign;
        }
      }
    });
  }

  void _cancelInlineText() {
    _inlineTextFocus.unfocus();
    setState(() => _isEditingText = false);
  }

  // ── Sticker picker (glass-styled) ──

  static const _stickers48 = [
    '😀', '😂', '😍', '😎', '😭', '🥳', '🤔', '🤩',
    '❤️', '🔥', '⭐', '💯', '✨', '🎉', '🚀', '👀',
    '👍', '👏', '🙌', '🙏', '💪', '🤝', '👌', '🫶',
    '🌸', '🌺', '🦋', '🌙', '☀️', '⚡', '🌊', '🍀',
    '🎵', '🎶', '💎', '👑', '🏆', '🎯', '💫', '🌈',
  ];

  Future<void> _addSticker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      builder: (ctx) => _GlassStickerSheet(stickers: _stickers48),
    );
    if (emoji == null || !mounted) return;
    _saveUndo();
    setState(() {
      _stickers.add(_StickerOverlay(
        id: _nextId++,
        emoji: emoji,
        position: const Offset(0.4, 0.45),
        scale: 1.0,
      ));
    });
  }

  // ── Poll (glass bottom sheet) ──

  Future<void> _addPoll() async {
    if (_polls.isNotEmpty) {
      _polls.clear();
    }
    final res = await showModalBottomSheet<_PollInputResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _GlassPollSheet(),
    );
    if (res == null || !mounted) return;
    _saveUndo();
    setState(() {
      _polls.add(_PollOverlay(
        id: _nextId++,
        question: res.question,
        optionA: res.optionA,
        optionB: res.optionB,
        position: const Offset(0.15, 0.4),
        scale: 1.0,
      ));
    });
  }

  // ── Question (glass bottom sheet) ──

  Future<void> _addQuestion() async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _GlassQuestionSheet(),
    );
    if (res == null || !mounted) return;
    _saveUndo();
    setState(() {
      _questions.add(_QuestionOverlay(
        id: _nextId++,
        prompt: res,
        position: const Offset(0.15, 0.5),
        scale: 1.0,
      ));
    });
  }

  void _removeOverlay(int id) {
    _saveUndo();
    setState(() {
      _texts.removeWhere((t) => t.id == id);
      _stickers.removeWhere((s) => s.id == id);
      _polls.removeWhere((p) => p.id == id);
      _questions.removeWhere((q) => q.id == id);
    });
  }

  void _clearAll() {
    if (_texts.isEmpty && _stickers.isEmpty && _polls.isEmpty && _questions.isEmpty) return;
    _saveUndo();
    HapticFeedback.mediumImpact();
    setState(() {
      _texts.clear();
      _stickers.clear();
      _polls.clear();
      _questions.clear();
    });
  }

  Future<void> _exportAndPop() async {
    if (_exporting) return;
    StoryPoll? interactivePoll;
    if (_polls.isNotEmpty) {
      final p = _polls.first;
      interactivePoll = StoryPoll(
        question: p.question,
        optionA: p.optionA,
        optionB: p.optionB,
        x: p.position.dx,
        y: p.position.dy,
      );
    }
    final savedPolls = List<_PollOverlay>.from(_polls);
    if (interactivePoll != null) {
      setState(() {
        _polls.clear();
        _exporting = true;
      });
    } else {
      setState(() => _exporting = true);
    }
    try {
      await Future.delayed(const Duration(milliseconds: 16));
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw 'Не удалось сжать картинку';
      }
      final bytes = byteData.buffer.asUint8List();
      if (!mounted) return;
      Navigator.of(context).pop(
        StoryEditorResult(bytes: bytes, poll: interactivePoll),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _polls.addAll(savedPolls);
        _exporting = false;
      });
      showSeeUSnackBar(context, 'Не удалось экспортировать: $e',
          tone: SeeUTone.danger);
    }
  }

  static const _colorSwatches = [
    Colors.white,
    Colors.yellow,
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.blue,
    Colors.cyan,
    Colors.green,
    Colors.black,
  ];

  static const _bgColors = [
    Colors.black,
    Colors.white,
    SeeUColors.accent,
    SeeUColors.amber,
    SeeUColors.success,
    SeeUColors.info,
    SeeUColors.error,
    SeeUColors.plum,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      _SquareIconButton(
                        icon: PhosphorIconsBold.caretLeft,
                        onTap: _exporting ? null : () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      const _ContextPill(),
                      const Spacer(),
                      // Undo button (visible only when history exists)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _undoStack.isNotEmpty ? 1.0 : 0.0,
                        child: _SquareIconButton(
                          icon: PhosphorIconsRegular.arrowCounterClockwise,
                          onTap: _undoStack.isNotEmpty ? _undo : null,
                        ),
                      ),
                    ],
                  ),
                ),

                // Canvas
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(SeeURadii.card),
                            boxShadow: SeeUShadows.lg,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(SeeURadii.card),
                            child: RepaintBoundary(
                              key: _canvasKey,
                              child: LayoutBuilder(builder: (ctx, constraints) {
                                return Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned.fill(
                                      child: Image.memory(
                                        widget.initialBytes,
                                        fit: BoxFit.cover,
                                        // Decode downscaled (≥ export size) — full-res
                                        // decode of a camera photo for a small preview OOMs.
                                        cacheWidth: 1200,
                                      ),
                                    ),
                                    ..._texts.map((t) => _buildTextOverlay(t, constraints)),
                                    ..._stickers.map((s) => _buildOverlay(
                                          key: ValueKey('s${s.id}'),
                                          child: Text(
                                            s.emoji,
                                            style: TextStyle(fontSize: 56 * s.scale),
                                          ),
                                          overlay: s,
                                          constraints: constraints,
                                          onUpdate: (pos, scale) => setState(() {
                                            s.position = pos;
                                            s.scale = scale;
                                          }),
                                          onDelete: () => _removeOverlay(s.id),
                                        )),
                                    ..._polls.map((p) => _buildOverlay(
                                          key: ValueKey('p${p.id}'),
                                          child: _PollWidget(poll: p),
                                          overlay: p,
                                          constraints: constraints,
                                          onUpdate: (pos, scale) => setState(() {
                                            p.position = pos;
                                            p.scale = scale;
                                          }),
                                          onDelete: () => _removeOverlay(p.id),
                                        )),
                                    ..._questions.map((q) => _buildOverlay(
                                          key: ValueKey('q${q.id}'),
                                          child: _QuestionWidget(question: q),
                                          overlay: q,
                                          constraints: constraints,
                                          onUpdate: (pos, scale) => setState(() {
                                            q.position = pos;
                                            q.scale = scale;
                                          }),
                                          onDelete: () => _removeOverlay(q.id),
                                        )),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Tools row — primary tools + subtle clear button
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Row(
                    children: [
                      _toolCard(
                        icon: Text('Aa',
                            style: SeeUTypography.displayXS.copyWith(
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w600)),
                        label: 'Текст',
                        accent: true,
                        onTap: _addText,
                      ),
                      _toolCard(
                        icon: const Text('😀', style: TextStyle(fontSize: 21)),
                        label: 'Стикер',
                        onTap: _addSticker,
                      ),
                      _toolCard(
                        icon: Icon(PhosphorIconsRegular.chartBar,
                            color: c.ink2, size: 21),
                        label: 'Опрос',
                        onTap: _addPoll,
                      ),
                      _toolCard(
                        icon: Icon(PhosphorIconsRegular.question,
                            color: c.ink2, size: 21),
                        label: 'Вопрос',
                        onTap: _addQuestion,
                      ),
                      // Clear-all tool card (dimmed when there's nothing to clear)
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: (_texts.isNotEmpty || _stickers.isNotEmpty ||
                              _polls.isNotEmpty || _questions.isNotEmpty) ? 1.0 : 0.3,
                          child: GestureDetector(
                            onTap: _clearAll,
                            child: Container(
                              height: 62,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: SeeUColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(SeeURadii.medium),
                                border: Border.all(
                                  color: SeeUColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 22,
                                    child: Center(
                                      child: Icon(PhosphorIconsRegular.eraser,
                                          color: SeeUColors.error, size: 21),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Очист.',
                                      style: SeeUTypography.micro
                                          .copyWith(color: SeeUColors.error)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Done button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: GestureDetector(
                    onTap: _exporting ? null : _exportAndPop,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        boxShadow: SeeUShadows.md,
                      ),
                      alignment: Alignment.center,
                      child: _exporting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.4),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Готово',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(width: 8),
                                Icon(PhosphorIconsBold.arrowRight,
                                    color: Colors.white, size: 18),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Inline text editor overlay
          if (_isEditingText)
            _InlineTextEditor(
              controller: _inlineTextCtrl,
              focusNode: _inlineTextFocus,
              selectedColor: _inlineColor,
              bgStyle: _inlineBgStyle,
              bgColor: _inlineBgColor,
              fontSize: _inlineFontSize,
              align: _inlineAlign,
              colorSwatches: _colorSwatches,
              bgColors: _bgColors,
              onColorChanged: (c) => setState(() => _inlineColor = c),
              onBgStyleChanged: (s) => setState(() => _inlineBgStyle = s),
              onBgColorChanged: (c) => setState(() => _inlineBgColor = c),
              onFontSizeChanged: (v) => setState(() => _inlineFontSize = v),
              onAlignChanged: (a) => setState(() => _inlineAlign = a),
              onConfirm: _confirmInlineText,
              onCancel: _cancelInlineText,
            ),
        ],
      ),
    );
  }

  // ── Text overlay with bgStyle support ──

  Widget _buildTextOverlay(_TextOverlay t, BoxConstraints constraints) {
    final textAlign = t.align == _TextAlign2.left
        ? TextAlign.left
        : t.align == _TextAlign2.right
            ? TextAlign.right
            : TextAlign.center;

    Widget textWidget = Text(
      t.text,
      textAlign: textAlign,
      // Editorial serif (Fraunces + Playfair-fallback для кириллицы) —
      // тот же характер, что displayM; размер/цвет управляются редактором.
      style: SeeUTypography.displayM.copyWith(
        color: t.color,
        fontSize: t.fontSize * t.scale,
        height: 1.2,
        shadows: t.bgStyle == _BgStyle.none
            ? const [Shadow(color: Colors.black54, blurRadius: 8)]
            : null,
      ),
    );

    Widget content;
    switch (t.bgStyle) {
      case _BgStyle.solid:
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.bgColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(SeeURadii.small),
          ),
          child: textWidget,
        );
      case _BgStyle.blur:
        content = ClipRRect(
          borderRadius: BorderRadius.circular(SeeURadii.small),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: Colors.black.withValues(alpha: 0.25),
              child: textWidget,
            ),
          ),
        );
      case _BgStyle.none:
        content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: textWidget,
        );
    }

    return _buildOverlay(
      key: ValueKey('t${t.id}'),
      child: content,
      overlay: t,
      constraints: constraints,
      onUpdate: (pos, scale) => setState(() {
        t.position = pos;
        t.scale = scale;
      }),
      onDelete: () => _removeOverlay(t.id),
      onDoubleTap: () => _editText(t),
    );
  }

  /// Wraps a draggable+scalable overlay.
  Widget _buildOverlay({
    required Key key,
    required Widget child,
    required _Overlay overlay,
    required BoxConstraints constraints,
    required void Function(Offset position, double scale) onUpdate,
    required VoidCallback onDelete,
    VoidCallback? onDoubleTap,
  }) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    return Positioned(
      key: key,
      left: overlay.position.dx * w,
      top: overlay.position.dy * h,
      child: GestureDetector(
        onDoubleTap: onDoubleTap ?? onDelete,
        onScaleStart: (_) {
          overlay.lastScale = overlay.scale;
        },
        onScaleUpdate: (details) {
          final newDx = (overlay.position.dx + details.focalPointDelta.dx / w)
              .clamp(0.0, 0.95);
          final newDy = (overlay.position.dy + details.focalPointDelta.dy / h)
              .clamp(0.0, 0.95);
          final newScale =
              (overlay.lastScale * details.scale).clamp(0.4, 4.0);
          onUpdate(Offset(newDx, newDy), newScale);
        },
        child: child,
      ),
    );
  }

  Widget _toolCard({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final c = context.seeuColors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 62,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: accent
                ? SeeUColors.accent.withValues(alpha: 0.10)
                : c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(
              color: accent
                  ? SeeUColors.accent.withValues(alpha: 0.3)
                  : c.line,
            ),
            boxShadow: accent ? null : SeeUShadows.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 22, child: Center(child: icon)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: accent ? SeeUColors.accent : c.ink2,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── History snapshot ──────────────────────────────────────────────────────────

class _HistorySnapshot {
  final List<_TextOverlay> texts;
  final List<_StickerOverlay> stickers;
  final List<_PollOverlay> polls;
  final List<_QuestionOverlay> questions;

  const _HistorySnapshot({
    required this.texts,
    required this.stickers,
    required this.polls,
    required this.questions,
  });
}

// ── Top-bar helpers ───────────────────────────────────────────────────────────

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SquareIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.small),
            border: Border.all(color: c.line),
            boxShadow: SeeUShadows.sm,
          ),
          child: Icon(icon, color: c.ink, size: 19),
        ),
      ),
    );
  }
}

/// Static context indicator («История») styled like the design's active tab.
class _ContextPill extends StatelessWidget {
  const _ContextPill();

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: c.line),
        boxShadow: SeeUShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsRegular.circleDashed,
              color: SeeUColors.accent, size: 15),
          const SizedBox(width: 7),
          Text('История',
              style: TextStyle(
                  color: c.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Glass sticker picker ──────────────────────────────────────────────────────

class _GlassStickerSheet extends StatefulWidget {
  final List<String> stickers;
  const _GlassStickerSheet({required this.stickers});

  @override
  State<_GlassStickerSheet> createState() => _GlassStickerSheetState();
}

class _GlassStickerSheetState extends State<_GlassStickerSheet> {
  int _selectedCat = 0;
  static const _cats = ['Смайлы', 'Активность', 'Природа', 'Жесты'];
  static const _catEmojis = [
    ['😀', '😂', '😍', '🥰', '😎', '🤩', '😴', '🤯', '🥳', '😭', '😤', '🫶',
     '🙃', '😇', '🤭', '😅', '😏', '🤔', '😒', '😳'],
    ['🔥', '❤️', '⭐', '🎉', '✨', '💫', '💥', '🌈', '🎵', '🎶', '👑', '💎',
     '🏆', '🎯', '💪', '⚡', '🌟', '🎊', '💯', '🛡️'],
    ['🌸', '🌺', '🦋', '🌙', '☀️', '⚡', '🌊', '🍀', '🌴', '🦄', '🐉', '🐬',
     '🦁', '🌻', '🍁', '❄️', '🌿', '🐝', '🦊', '🌵'],
    ['👍', '👎', '🙌', '🤝', '✌️', '🫵', '💪', '👏', '🙏', '🤙', '☝️', '🫂',
     '🤜', '🤛', '👊', '✊', '🤞', '🤟', '🤘', '👋'],
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.5),
            ),
          ),
          child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ИСТОРИЯ · ОФОРМЛЕНИЕ',
                      style: SeeUTypography.kicker
                          .copyWith(color: SeeUColors.accent)),
                  const SizedBox(height: 4),
                  Text('Стикеры',
                      style: SeeUTypography.displayS.copyWith(color: c.ink)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Category tabs
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == _selectedCat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCat = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? SeeUColors.accent.withValues(alpha: 0.12)
                            : c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(
                          color: selected
                              ? SeeUColors.accent.withValues(alpha: 0.5)
                              : c.line,
                        ),
                      ),
                      child: Text(
                        _cats[i],
                        style: TextStyle(
                          color: selected ? SeeUColors.accent : c.ink3,
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Emoji grid
            SizedBox(
              height: 220,
              child: GridView.count(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                crossAxisCount: 7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: _catEmojis[_selectedCat].map((e) {
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(e);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.small),
                        border: Border.all(color: c.line),
                      ),
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

// ── Glass poll sheet ──────────────────────────────────────────────────────────

class _GlassPollSheet extends StatefulWidget {
  const _GlassPollSheet();

  @override
  State<_GlassPollSheet> createState() => _GlassPollSheetState();
}

class _GlassPollSheetState extends State<_GlassPollSheet> {
  final _questionCtrl = TextEditingController();
  final _optACtrl = TextEditingController(text: 'Да');
  final _optBCtrl = TextEditingController(text: 'Нет');

  @override
  void dispose() {
    _questionCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final q = _questionCtrl.text.trim();
    final a = _optACtrl.text.trim();
    final b = _optBCtrl.text.trim();
    if (q.isEmpty || a.isEmpty || b.isEmpty) {
      showSeeUSnackBar(context, 'Заполните вопрос и оба варианта',
          tone: SeeUTone.danger);
      return;
    }
    Navigator.pop(context, _PollInputResult(question: q, optionA: a, optionB: b));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('ИСТОРИЯ · ИНТЕРАКТИВ',
              style: SeeUTypography.kicker.copyWith(color: SeeUColors.accent)),
          const SizedBox(height: 4),
          Text('Опрос', style: SeeUTypography.displayS.copyWith(color: c.ink)),
          const SizedBox(height: 16),
          Text('Вопрос', style: SeeUTypography.micro.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          _field(_questionCtrl, 'Например: Что выберете?', autofocus: true),
          const SizedBox(height: 14),
          Text('Варианты', style: SeeUTypography.micro.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _field(_optACtrl, 'Вариант А')),
              const SizedBox(width: 10),
              Expanded(child: _field(_optBCtrl, 'Вариант Б',
                  action: TextInputAction.done)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.4),
                      blurRadius: 16, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('Добавить опрос',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool autofocus = false, TextInputAction action = TextInputAction.next}) {
    final c = context.seeuColors;
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      textInputAction: action,
      maxLength: 80,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: SeeUTypography.body.copyWith(color: c.ink4),
        counterText: '',
        filled: true,
        fillColor: c.surface2,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SeeURadii.small),
            borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ── Glass question sheet ──────────────────────────────────────────────────────

class _GlassQuestionSheet extends StatefulWidget {
  const _GlassQuestionSheet();

  @override
  State<_GlassQuestionSheet> createState() => _GlassQuestionSheetState();
}

class _GlassQuestionSheetState extends State<_GlassQuestionSheet> {
  final _ctrl = TextEditingController(text: 'Спросите меня что угодно');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('ИСТОРИЯ · ИНТЕРАКТИВ',
              style: SeeUTypography.kicker.copyWith(color: SeeUColors.accent)),
          const SizedBox(height: 4),
          Text('Вопрос', style: SeeUTypography.displayS.copyWith(color: c.ink)),
          const SizedBox(height: 16),
          Text('Текст вопроса', style: SeeUTypography.micro.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
            },
            decoration: InputDecoration(
              hintText: 'Что показать viewer\'у...',
              hintStyle: SeeUTypography.body.copyWith(color: c.ink4),
              counterText: '',
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                  borderSide: BorderSide.none),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                final v = _ctrl.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(context, v);
              },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.4),
                      blurRadius: 16, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('Добавить вопрос',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

// ── Overlay model classes ─────────────────────────────────────────────────────

abstract class _Overlay {
  int id;
  Offset position;
  double scale;
  double lastScale = 1.0;
  _Overlay({required this.id, required this.position, required this.scale});
}

class _TextOverlay extends _Overlay {
  String text;
  Color color;
  double fontSize;
  _BgStyle bgStyle;
  Color bgColor;
  _TextAlign2 align;

  _TextOverlay({
    required super.id,
    required this.text,
    required this.color,
    this.fontSize = 28.0,
    this.bgStyle = _BgStyle.none,
    this.bgColor = Colors.black,
    this.align = _TextAlign2.center,
    required super.position,
    required super.scale,
  });

  _TextOverlay copy() => _TextOverlay(
        id: id,
        text: text,
        color: color,
        fontSize: fontSize,
        bgStyle: bgStyle,
        bgColor: bgColor,
        align: align,
        position: position,
        scale: scale,
      )..lastScale = lastScale;
}

class _StickerOverlay extends _Overlay {
  String emoji;
  _StickerOverlay({
    required super.id,
    required this.emoji,
    required super.position,
    required super.scale,
  });

  _StickerOverlay copy() => _StickerOverlay(
        id: id,
        emoji: emoji,
        position: position,
        scale: scale,
      )..lastScale = lastScale;
}

class _PollOverlay extends _Overlay {
  String question;
  String optionA;
  String optionB;
  _PollOverlay({
    required super.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    required super.position,
    required super.scale,
  });

  _PollOverlay copy() => _PollOverlay(
        id: id,
        question: question,
        optionA: optionA,
        optionB: optionB,
        position: position,
        scale: scale,
      )..lastScale = lastScale;
}

class _QuestionOverlay extends _Overlay {
  String prompt;
  _QuestionOverlay({
    required super.id,
    required this.prompt,
    required super.position,
    required super.scale,
  });

  _QuestionOverlay copy() => _QuestionOverlay(
        id: id,
        prompt: prompt,
        position: position,
        scale: scale,
      )..lastScale = lastScale;
}

class _PollInputResult {
  final String question;
  final String optionA;
  final String optionB;
  _PollInputResult({
    required this.question,
    required this.optionA,
    required this.optionB,
  });
}

// ── Question overlay widget ───────────────────────────────────────────────────

class _QuestionWidget extends StatelessWidget {
  final _QuestionOverlay question;
  const _QuestionWidget({required this.question});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: question.scale,
      alignment: Alignment.topLeft,
      // Стекло над медиа: blur + white→black градиент + светлый бордюр.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 240,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  question.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // Вложенный элемент — плоский, без своего blur.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Center(
                    child: Text(
                      'Введите ответ...',
                      style: SeeUTypography.micro.copyWith(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75),
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

// ── Poll overlay widget ───────────────────────────────────────────────────────

class _PollWidget extends StatelessWidget {
  final _PollOverlay poll;
  const _PollWidget({required this.poll});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: poll.scale,
      alignment: Alignment.topLeft,
      // Стекло над медиа: blur + white→black градиент + светлый бордюр.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  poll.question,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Вложенные чипы — плоские, без своего blur.
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(SeeURadii.small),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          poll.optionA,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.micro.copyWith(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(SeeURadii.small),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          poll.optionB,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.micro.copyWith(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Enhanced inline text editor ───────────────────────────────────────────────

/// Full-screen inline text editor: dark scrim, centered TextField (large text),
/// color picker, background style, font size slider, alignment buttons.
class _InlineTextEditor extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color selectedColor;
  final _BgStyle bgStyle;
  final Color bgColor;
  final double fontSize;
  final _TextAlign2 align;
  final List<Color> colorSwatches;
  final List<Color> bgColors;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<_BgStyle> onBgStyleChanged;
  final ValueChanged<Color> onBgColorChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<_TextAlign2> onAlignChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _InlineTextEditor({
    required this.controller,
    required this.focusNode,
    required this.selectedColor,
    required this.bgStyle,
    required this.bgColor,
    required this.fontSize,
    required this.align,
    required this.colorSwatches,
    required this.bgColors,
    required this.onColorChanged,
    required this.onBgStyleChanged,
    required this.onBgColorChanged,
    required this.onFontSizeChanged,
    required this.onAlignChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  TextAlign get _textAlign => align == _TextAlign2.left
      ? TextAlign.left
      : align == _TextAlign2.right
          ? TextAlign.right
          : TextAlign.center;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Background
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onConfirm,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.82)),
              ),
            ),

            Column(
              children: [
                SizedBox(height: topPad + 8),

                // Top row: cancel + done
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: onCancel,
                          icon: const Icon(PhosphorIconsRegular.x, color: Colors.white),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: onConfirm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius: BorderRadius.circular(SeeURadii.pill),
                            ),
                            child: const Text('Готово',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Text color swatches
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: colorSwatches.map((c) {
                        final isSelected = c.toARGB32() == selectedColor.toARGB32();
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onColorChanged(c);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: isSelected ? 30 : 26,
                            height: isSelected ? 30 : 26,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? SeeUColors.accent
                                    : Colors.white.withValues(alpha: 0.4),
                                width: isSelected ? 2.5 : 1.5,
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(
                                      color: SeeUColors.accent.withValues(alpha: 0.5),
                                      blurRadius: 6)]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Background style selector
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BgStyleBtn(
                          label: 'Без фона',
                          icon: PhosphorIconsRegular.textT,
                          selected: bgStyle == _BgStyle.none,
                          onTap: () => onBgStyleChanged(_BgStyle.none),
                        ),
                        const SizedBox(width: 8),
                        _BgStyleBtn(
                          label: 'Размытие',
                          icon: PhosphorIconsRegular.drop,
                          selected: bgStyle == _BgStyle.blur,
                          onTap: () => onBgStyleChanged(_BgStyle.blur),
                        ),
                        const SizedBox(width: 8),
                        _BgStyleBtn(
                          label: 'Заливка',
                          icon: PhosphorIconsRegular.paintBucket,
                          selected: bgStyle == _BgStyle.solid,
                          onTap: () => onBgStyleChanged(_BgStyle.solid),
                        ),
                      ],
                    ),
                  ),
                ),

                // Background color swatches (when solid is selected)
                if (bgStyle == _BgStyle.solid)
                  GestureDetector(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: bgColors.map((c) {
                          final sel = c.toARGB32() == bgColor.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onBgColorChanged(c);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: sel ? 28 : 24,
                              height: sel ? 28 : 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                  width: sel ? 2.5 : 1,
                                ),
                                boxShadow: sel
                                    ? [BoxShadow(
                                        color: c.withValues(alpha: 0.5),
                                        blurRadius: 8)]
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                // Text field
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          maxLines: null,
                          textAlign: _textAlign,
                          // Тот же серифный editorial-пресет, что и рендер
                          // текст-оверлея на канвасе.
                          style: SeeUTypography.displayM.copyWith(
                            color: selectedColor,
                            fontSize: fontSize,
                            height: 1.2,
                            shadows: bgStyle == _BgStyle.none
                                ? const [Shadow(color: Colors.black54, blurRadius: 8)]
                                : null,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Введите текст...',
                            hintStyle: SeeUTypography.displayM.copyWith(
                              color: Colors.white.withValues(alpha: 0.38),
                              fontSize: fontSize,
                            ),
                          ),
                          onSubmitted: (_) => onConfirm(),
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ),
                  ),
                ),

                // Font size slider
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsRegular.textT,
                            color: Colors.white54, size: 14),
                        Expanded(
                          child: Slider(
                            value: fontSize,
                            min: 14,
                            max: 72,
                            activeColor: SeeUColors.accent,
                            inactiveColor: Colors.white.withValues(alpha: 0.25),
                            onChanged: onFontSizeChanged,
                          ),
                        ),
                        const Icon(PhosphorIconsBold.textT,
                            color: Colors.white70, size: 22),
                      ],
                    ),
                  ),
                ),

                // Alignment + confirm row
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottom > 0 ? 8 : 28),
                    child: Row(
                      children: [
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignLeft,
                          selected: align == _TextAlign2.left,
                          onTap: () => onAlignChanged(_TextAlign2.left),
                        ),
                        const SizedBox(width: 8),
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignCenter,
                          selected: align == _TextAlign2.center,
                          onTap: () => onAlignChanged(_TextAlign2.center),
                        ),
                        const SizedBox(width: 8),
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignRight,
                          selected: align == _TextAlign2.right,
                          onTap: () => onAlignChanged(_TextAlign2.right),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: onConfirm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius: BorderRadius.circular(SeeURadii.pill),
                            ),
                            child: const Text(
                              'Готово',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: bottom),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _BgStyleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BgStyleBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: selected
                ? SeeUColors.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: selected ? SeeUColors.accent : Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? SeeUColors.accent : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AlignBtn({required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Icon(icon, size: 18,
            color: selected ? Colors.white : Colors.white54),
      ),
    );
  }
}
