import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../providers/sticker_editor_provider.dart';
import 'color_picker_sheet.dart';
import 'font_picker_sheet.dart';
import 'layers_panel_sheet.dart';

/// Нижняя панель инструментов редактора стикера.
class EditorBottomBar extends ConsumerWidget {
  final VoidCallback onAddText;

  const EditorBottomBar({super.key, required this.onAddText});

  void _showSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stickerEditorProvider);
    final notifier = ref.read(stickerEditorProvider.notifier);

    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Undo / Redo ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _UndoRedoButton(
                icon: PhosphorIconsRegular.arrowCounterClockwise,
                enabled: notifier.canUndo,
                onTap: notifier.undo,
              ),
              _UndoRedoButton(
                icon: PhosphorIconsRegular.arrowClockwise,
                enabled: notifier.canRedo,
                onTap: notifier.redo,
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ── Основные инструменты ────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToolButton(
                icon: PhosphorIconsRegular.textT,
                label: 'Текст',
                onTap: onAddText,
              ),
              _ToolButton(
                icon: PhosphorIconsRegular.textAa,
                label: 'Шрифт',
                enabled: state.activeLayer != null,
                onTap: () => _showSheet(context, const FontPickerSheet()),
              ),
              _ToolButton(
                icon: PhosphorIconsRegular.palette,
                label: 'Цвет',
                enabled: state.activeLayer != null,
                onTap: () => _showSheet(context, const ColorPickerSheet()),
              ),
              _ToolButton(
                icon: PhosphorIconsRegular.stack,
                label: 'Слои',
                badge: state.layers.isNotEmpty ? '${state.layers.length}' : null,
                onTap: () => _showSheet(context, const LayersPanelSheet()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Кнопка инструмента ───────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? Colors.white : Colors.white30;
    final labelColor = enabled ? Colors.white70 : Colors.white24;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: iconColor, size: 24),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Кнопки undo/redo ─────────────────────────────────────────────

class _UndoRedoButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _UndoRedoButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.white : Colors.white24,
        ),
      ),
    );
  }
}
