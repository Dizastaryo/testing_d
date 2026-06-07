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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
        : layer.text.length > 30
            ? '${layer.text.substring(0, 30)}…'
            : layer.text;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? SeeUColors.accent.withValues(alpha: 0.1)
              : c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
            color: isActive ? SeeUColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // ── Цветной кружок ─────────────────────────────
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: layer.color,
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 1),
              ),
            ),
            const SizedBox(width: 10),

            // ── Предпросмотр текста ─────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview,
                    style: SeeUTypography.body.copyWith(
                      color: isActive ? SeeUColors.accent : c.ink,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
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

            // ── Действия ────────────────────────────────────
            _IconBtn(
              icon: PhosphorIconsRegular.arrowUp,
              enabled: canMoveUp,
              onTap: onMoveUp,
              c: c,
            ),
            _IconBtn(
              icon: PhosphorIconsRegular.arrowDown,
              enabled: canMoveDown,
              onTap: onMoveDown,
              c: c,
            ),
            _IconBtn(
              icon: PhosphorIconsRegular.copy,
              enabled: true,
              onTap: onDuplicate,
              c: c,
            ),
            _IconBtn(
              icon: PhosphorIconsRegular.trash,
              enabled: true,
              onTap: onDelete,
              c: c,
              danger: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final SeeUThemeColors c;
  final bool danger;

  const _IconBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.c,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? c.ink4
        : danger
            ? Colors.red.shade400
            : c.ink2;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
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
