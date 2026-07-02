import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/text_layer.dart';
import '../providers/sticker_editor_provider.dart';
import 'text_layer_handle.dart';

/// Холст редактора стикера.
///
/// Занимает всё доступное пространство. Фоновое изображение вписывается
/// через [BoxFit.contain]. Текстовые слои позиционируются поверх
/// с нормализованными координатами (0–1 по обеим осям).
class StickerCanvas extends ConsumerWidget {
  final ImageProvider backgroundImage;

  /// Вызывается при тапе на слой — родитель открывает поле ввода текста.
  final void Function(TextLayer layer)? onEditText;

  const StickerCanvas({
    super.key,
    required this.backgroundImage,
    this.onEditText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(stickerEditorProvider);
    final notifier = ref.read(stickerEditorProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          // Тап по пустому месту — снимает выделение со всех слоёв.
          onTap: () => notifier.setActive(null),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // ── Фоновое изображение ──────────────────────────────
              Positioned.fill(
                child: Image(
                  image: backgroundImage,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),

              // ── Текстовые слои ───────────────────────────────────
              // Слои в списке — в порядке от нижнего к верхнему.
              for (final layer in editorState.layers)
                TextLayerHandle(
                  key: ValueKey(layer.id),
                  layer: layer,
                  canvasSize: canvasSize,
                  isActive: layer.id == editorState.activeLayerId,
                  onEditText: onEditText,
                ),
            ],
          ),
        );
      },
    );
  }
}
