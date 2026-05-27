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

/// Полно-экранный редактор сторис: фото как фон + draggable текст/стикеры.
/// На «Готово» делает `RepaintBoundary.toImage()` → возвращает PNG-bytes +
/// (опционально) interactive poll через `Navigator.pop(StoryEditorResult)`.
///
/// STORY-3: Poll-overlay'и НЕ растеризуются — берётся первый из _polls,
/// конвертируется в StoryPoll и возвращается отдельно. Viewer на бэке
/// рендерит интерактивные кнопки и собирает голоса.
///
/// V1: только photo (Uint8List). Video с overlay'ями требует ffmpeg-overlay
/// pass, скипнут (открывается обычная MediaPrepare без редактора).
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

  static const _stickers48 = [
    '😀', '😂', '😍', '😎', '😭', '🥳', '🤔', '🤩',
    '❤️', '🔥', '⭐', '💯', '✨', '🎉', '🚀', '👀',
    '👍', '👏', '🙌', '🙏', '💪', '🤝', '👌', '🫶',
  ];

  Future<void> _addText() async {
    final result = await _showTextInputDialog();
    if (result == null || result.text.trim().isEmpty) return;
    setState(() {
      _texts.add(_TextOverlay(
        id: _nextId++,
        text: result.text,
        color: result.color,
        // Изначально в центре canvas'а — потом юзер таскает.
        position: const Offset(0.4, 0.45),
        scale: 1.0,
      ));
    });
  }

  Future<_TextInputResult?> _showTextInputDialog() async {
    final controller = TextEditingController();
    Color color = Colors.white;
    final res = await showDialog<_TextInputResult>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(builder: (sbCtx, sbSet) {
        return AlertDialog(
          title: const Text('Добавить текст'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 200,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Напишите что-нибудь',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Colors.white,
                  Colors.black,
                  SeeUColors.accent,
                  Colors.yellow,
                  Colors.cyan,
                  Colors.pinkAccent,
                ].map((c) => GestureDetector(
                  onTap: () => sbSet(() => color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == c ? Colors.black : Colors.grey,
                        width: color == c ? 3 : 1,
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
              onPressed: () => Navigator.of(dlgCtx).pop(
                  _TextInputResult(text: controller.text, color: color)),
              child: const Text('Добавить'),
            ),
          ],
        );
      }),
    );
    return res;
  }

  Future<void> _addSticker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _stickers48
                    .map((e) => GestureDetector(
                          onTap: () => Navigator.of(sheetCtx).pop(e),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(e,
                                  style: const TextStyle(fontSize: 32)),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null) return;
    setState(() {
      _stickers.add(_StickerOverlay(
        id: _nextId++,
        emoji: emoji,
        position: const Offset(0.4, 0.45),
        scale: 1.0,
      ));
    });
  }

  Future<void> _addPoll() async {
    // STORY-3: только один interactive poll на сторис. Tap «Опрос» при уже
    // существующем — заменяет (как в Insta).
    if (_polls.isNotEmpty) {
      _polls.clear();
    }
    final qCtrl = TextEditingController();
    final aCtrl = TextEditingController(text: 'Да');
    final bCtrl = TextEditingController(text: 'Нет');
    final res = await showDialog<_PollInputResult>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Опрос'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qCtrl,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: 'Вопрос...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: aCtrl,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      hintText: 'Вариант A',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: bCtrl,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      hintText: 'Вариант B',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () {
              if (qCtrl.text.trim().isEmpty ||
                  aCtrl.text.trim().isEmpty ||
                  bCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.of(dlgCtx).pop(_PollInputResult(
                question: qCtrl.text.trim(),
                optionA: aCtrl.text.trim(),
                optionB: bCtrl.text.trim(),
              ));
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (res == null) return;
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

  void _removeOverlay(int id) {
    setState(() {
      _texts.removeWhere((t) => t.id == id);
      _stickers.removeWhere((s) => s.id == id);
      _polls.removeWhere((p) => p.id == id);
      _questions.removeWhere((q) => q.id == id);
    });
  }

  Future<void> _addQuestion() async {
    final ctrl = TextEditingController(text: 'Спросите меня что угодно');
    final res = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Вопрос viewer\'ам'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'Что показать viewer\'у...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.of(dlgCtx).pop(v);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (res == null) return;
    setState(() {
      _questions.add(_QuestionOverlay(
        id: _nextId++,
        prompt: res,
        position: const Offset(0.15, 0.5),
        scale: 1.0,
      ));
    });
  }

  Future<void> _exportAndPop() async {
    if (_exporting) return;
    // STORY-3: poll выносим из растрового кадра — отдадим в StoryEditorResult.
    // Сначала capture poll-data (нужна позиция), потом временно очищаем
    // _polls перед toImage чтобы он не попал в PNG. После — возвращаем.
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
      // Дать одну рамку чтобы Stack пересобрался без poll'ов.
      await Future.delayed(const Duration(milliseconds: 16));
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // pixelRatio 2.0 — баланс между качеством и размером файла.
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
      // Восстановить poll'ы для UI чтобы юзер мог попробовать снова.
      setState(() {
        _polls.addAll(savedPolls);
        _exporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar — Cancel + «Готово»
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _exporting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsRegular.x, color: Colors.white),
                  ),
                  const Spacer(),
                  if (_exporting)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: SeeUColors.accent,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: SeeUColors.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      onPressed: _exportAndPop,
                      icon:
                          const Icon(PhosphorIconsBold.check, size: 18, color: Colors.white),
                      label: const Text('Готово',
                          style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
            // Canvas: фото + overlay'и. Story-aspect 9:16, но canvas сам
            // адаптируется к bytes; центрируем BoxFit.contain.
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: LayoutBuilder(builder: (ctx, constraints) {
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // Фон-фото — растянуто на всю площадь canvas'а.
                          Positioned.fill(
                            child: Image.memory(
                              widget.initialBytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Overlay'и поверх — drag-handlers, double-tap = delete.
                          ..._texts.map((t) => _buildOverlay(
                                key: ValueKey('t${t.id}'),
                                child: Text(
                                  t.text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: t.color,
                                    fontSize: 28 * t.scale,
                                    fontWeight: FontWeight.w700,
                                    shadows: const [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 4,
                                        color: Colors.black54,
                                      ),
                                    ],
                                  ),
                                ),
                                overlay: t,
                                constraints: constraints,
                                onUpdate: (pos, scale) {
                                  setState(() {
                                    t.position = pos;
                                    t.scale = scale;
                                  });
                                },
                                onDelete: () => _removeOverlay(t.id),
                              )),
                          ..._stickers.map((s) => _buildOverlay(
                                key: ValueKey('s${s.id}'),
                                child: Text(
                                  s.emoji,
                                  style: TextStyle(fontSize: 56 * s.scale),
                                ),
                                overlay: s,
                                constraints: constraints,
                                onUpdate: (pos, scale) {
                                  setState(() {
                                    s.position = pos;
                                    s.scale = scale;
                                  });
                                },
                                onDelete: () => _removeOverlay(s.id),
                              )),
                          ..._polls.map((p) => _buildOverlay(
                                key: ValueKey('p${p.id}'),
                                child: _PollWidget(poll: p),
                                overlay: p,
                                constraints: constraints,
                                onUpdate: (pos, scale) {
                                  setState(() {
                                    p.position = pos;
                                    p.scale = scale;
                                  });
                                },
                                onDelete: () => _removeOverlay(p.id),
                              )),
                          ..._questions.map((q) => _buildOverlay(
                                key: ValueKey('q${q.id}'),
                                child: _QuestionWidget(question: q),
                                overlay: q,
                                constraints: constraints,
                                onUpdate: (pos, scale) {
                                  setState(() {
                                    q.position = pos;
                                    q.scale = scale;
                                  });
                                },
                                onDelete: () => _removeOverlay(q.id),
                              )),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            // Tools row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _toolButton(
                    icon: const Text('Aa',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    label: 'Текст',
                    onTap: _addText,
                  ),
                  _toolButton(
                    icon: const Text('😀', style: TextStyle(fontSize: 22)),
                    label: 'Стикер',
                    onTap: _addSticker,
                  ),
                  _toolButton(
                    icon: Icon(PhosphorIconsBold.chartBar,
                        color: Colors.white, size: 22),
                    label: 'Опрос',
                    onTap: _addPoll,
                  ),
                  _toolButton(
                    icon: Icon(PhosphorIconsBold.question,
                        color: Colors.white, size: 22),
                    label: 'Вопрос',
                    onTap: _addQuestion,
                  ),
                  _toolButton(
                    icon: Icon(PhosphorIcons.trash(), color: Colors.white),
                    label: 'Очистить',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _texts.clear();
                        _stickers.clear();
                        _polls.clear();
                        _questions.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps a draggable+scalable overlay. position и scale — нормализованные
  /// 0..1 относительно canvas-constraints. double-tap = удалить.
  Widget _buildOverlay({
    required Key key,
    required Widget child,
    required _Overlay overlay,
    required BoxConstraints constraints,
    required void Function(Offset position, double scale) onUpdate,
    required VoidCallback onDelete,
  }) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    return Positioned(
      key: key,
      left: overlay.position.dx * w,
      top: overlay.position.dy * h,
      child: GestureDetector(
        onDoubleTap: onDelete,
        onScaleStart: (_) {
          overlay.lastScale = overlay.scale;
        },
        onScaleUpdate: (details) {
          // Position drag через focalPointDelta — works one-finger тоже.
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

  Widget _toolButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Общий базовый класс для overlay'ев (Text/Sticker). Mutable — менеджмент
/// state через setState родителя.
abstract class _Overlay {
  int id;
  Offset position; // нормализованные 0..1
  double scale;
  double lastScale = 1.0;
  _Overlay({required this.id, required this.position, required this.scale});
}

class _TextOverlay extends _Overlay {
  String text;
  Color color;
  _TextOverlay({
    required super.id,
    required this.text,
    required this.color,
    required super.position,
    required super.scale,
  });
}

class _StickerOverlay extends _Overlay {
  String emoji;
  _StickerOverlay({
    required super.id,
    required this.emoji,
    required super.position,
    required super.scale,
  });
}

/// Poll-overlay: вопрос + 2 варианта. Instagram-style. Голосовать viewer
/// сможет в будущем (нужен polls-API на бэке); пока — visual-only.
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
}

/// Question-overlay: «Спросите меня что угодно» с одним свободным input'ом
/// у viewer'а. На canvas автора виден как карточка с заголовком + placeholder.
class _QuestionOverlay extends _Overlay {
  String prompt;
  _QuestionOverlay({
    required super.id,
    required this.prompt,
    required super.position,
    required super.scale,
  });
}

class _TextInputResult {
  final String text;
  final Color color;
  _TextInputResult({required this.text, required this.color});
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

/// Question-overlay визуал — заголовок-prompt + «Спросите...» plaholder
/// в стиле Instagram «Sticker Question». Голосование не доступно в v1.
class _QuestionWidget extends StatelessWidget {
  final _QuestionOverlay question;
  const _QuestionWidget({required this.question});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: question.scale,
      alignment: Alignment.topLeft,
      child: Container(
        width: 240,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: SeeUColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'Введите ответ...',
                  style: TextStyle(
                    color: SeeUColors.accent.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

/// Визуал poll-overlay'я. Белая карточка 240×96, accent ramка, вопрос сверху,
/// две кнопки внизу. Scale применяется через Transform.scale в _buildOverlay.
class _PollWidget extends StatelessWidget {
  final _PollOverlay poll;
  const _PollWidget({required this.poll});

  @override
  Widget build(BuildContext context) {
    final s = poll.scale;
    return Transform.scale(
      scale: s,
      alignment: Alignment.topLeft,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      poll.optionA,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SeeUColors.accent,
                        fontSize: 12,
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
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      poll.optionB,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
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
    );
  }
}
