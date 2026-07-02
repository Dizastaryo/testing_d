import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../models/text_layer.dart';
import '../providers/sticker_editor_provider.dart';

class LayersPanelSheet extends ConsumerWidget {
  const LayersPanelSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final state = ref.watch(stickerEditorProvider);
    final notifier = ref.read(stickerEditorProvider.notifier);

    // Слои в UI показываем сверху вниз = верхний слой первым (reversed).
    final layers = state.layers.reversed.toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.50,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      child: Column(
        children: [
          _Handle(c: c),

          // ── Заголовок + кнопка добавить ────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Слои',
                    style: SeeUTypography.subtitle.copyWith(color: c.ink),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    notifier.addLayer();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.plus,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Список слоёв ────────────────────────────────────
          Expanded(
            child: layers.isEmpty
                ? Center(
                    child: Text(
                      'Нет слоёв.\nНажми + чтобы добавить текст.',
                      textAlign: TextAlign.center,
                      style: SeeUTypography.body.copyWith(color: c.ink3),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: layers.length,
                    itemBuilder: (ctx, i) {
                      final layer = layers[i];
                      final isActive = layer.id == state.activeLayerId;
                      // Индекс в оригинальном списке (для операций move).
                      final originalIndex =
                          state.layers.length - 1 - i;
                      final canMoveUp = originalIndex < state.layers.length - 1;
                      final canMoveDown = originalIndex > 0;

                      return _LayerItem(
                        key: ValueKey(layer.id),
                        layer: layer,
                        isActive: isActive,
                        canMoveUp: canMoveUp,
                        canMoveDown: canMoveDown,
                        c: c,
                        onTap: () {
                          notifier.setActive(layer.id);
                          Navigator.pop(context);
                        },
                        onDelete: () => notifier.deleteLayer(layer.id),
                        onDuplicate: () {
                          notifier.duplicateLayer(layer.id);
                        },
                        onMoveUp: () => notifier.moveLayerUp(layer.id),
                        onMoveDown: () => notifier.moveLayerDown(layer.id),
                      );
                    },
                  ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ─── Элемент слоя ─────────────────────────────────────────────────

class _LayerItem extends StatelessWidget {
  final TextLayer layer;
  final bool isActive;
  final bool canMoveUp;
  final bool canMoveDown;
  final SeeUThemeColors c;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _LayerItem({
    super.key,
    required this.layer,
    required this.isActive,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.c,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final preview = layer.text.isEmpty
        ? '(пустой)'
        : layer.text.length > 28
            ? '${layer.text.substring(0, 28)}…'
            : layer.text;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? c.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // ── Drag handle ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                PhosphorIconsRegular.dotsSixVertical,
                color: c.ink4,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),

            // ── Checker thumbnail ──────────────────────────
            _LayerThumb(layer: layer),
            const SizedBox(width: 12),

            // ── Название + шрифт ────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview,
                    style: SeeUTypography.body.copyWith(
                      color: isActive ? c.ink : c.ink,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    layer.fontFamily,
                    style: SeeUTypography.micro.copyWith(color: c.ink3),
                  ),
                ],
              ),
            ),

            // ── Видимость ────────────────────────────────────
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  PhosphorIconsRegular.eye,
                  color: c.ink3,
                  size: 18,
                ),
              ),
            ),

            // ── Меню ─────────────────────────────────────────
            PopupMenuButton<String>(
              icon: Icon(
                PhosphorIconsRegular.dotsThreeVertical,
                color: c.ink3,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'up') {
                  onMoveUp();
                } else if (value == 'down') {
                  onMoveDown();
                } else if (value == 'dup') {
                  onDuplicate();
                } else if (value == 'del') {
                  onDelete();
                }
              },
              itemBuilder: (ctx) => [
                if (canMoveUp)
                  const PopupMenuItem(value: 'up', child: Text('Переместить выше')),
                if (canMoveDown)
                  const PopupMenuItem(value: 'down', child: Text('Переместить ниже')),
                const PopupMenuItem(value: 'dup', child: Text('Дублировать')),
                PopupMenuItem(
                  value: 'del',
                  child: Text('Удалить', style: TextStyle(color: SeeUColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Checker thumbnail ────────────────────────────────────────────

class _LayerThumb extends StatelessWidget {
  final TextLayer layer;
  const _LayerThumb({required this.layer});

  @override
  Widget build(BuildContext context) {
    final thumbText = layer.text.isEmpty
        ? 'Aa'
        : layer.text.substring(0, layer.text.length.clamp(0, 2)).toUpperCase();

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8CC), width: 0.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: CustomPaint(
        painter: _CheckerPainter(),
        child: Center(
          child: Text(
            thumbText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: layer.color,
              shadows: const [
                Shadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cellSize = 8;
    final paint = Paint();
    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isLight = ((x ~/ cellSize) + (y ~/ cellSize)) % 2 == 0;
        paint.color = isLight ? Colors.white : const Color(0xFFE8E8E8);
        canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Handle ───────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  final SeeUThemeColors c;
  const _Handle({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: c.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
