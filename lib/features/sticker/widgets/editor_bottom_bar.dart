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
    final c = context.seeuColors;
    final state = ref.watch(stickerEditorProvider);
    final hasActive = state.activeLayer != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SeeURadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active layer quick-access row
            if (hasActive) ...[
              _ActiveLayerBar(c: c),
              Divider(height: 1, color: c.line),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ToolButton(
                    icon: PhosphorIconsRegular.textAa,
                    label: 'Текст',
                    active: true,
                    c: c,
                    onTap: onAddText,
                  ),
                  _ToolButton(
                    icon: PhosphorIconsRegular.textT,
                    label: 'Шрифт',
                    enabled: hasActive,
                    c: c,
                    onTap: () => _showSheet(context, const FontPickerSheet()),
                  ),
                  _ToolButton(
                    icon: PhosphorIconsRegular.palette,
                    label: 'Цвет',
                    enabled: hasActive,
                    c: c,
                    onTap: () => _showSheet(context, const ColorPickerSheet()),
                  ),
                  _ToolButton(
                    icon: PhosphorIconsRegular.stack,
                    label: 'Слои',
                    badge: state.layers.isNotEmpty
                        ? '${state.layers.length}'
                        : null,
                    c: c,
                    onTap: () =>
                        _showSheet(context, const LayersPanelSheet()),
                  ),
                  _ToolButton(
                    icon: PhosphorIconsRegular.smiley,
                    label: 'Эмодзи',
                    c: c,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Быстрая панель активного слоя ───────────────────────────────

class _ActiveLayerBar extends ConsumerWidget {
  final SeeUThemeColors c;

  const _ActiveLayerBar({required this.c});

  static const _fonts = [
    'Roboto', 'Montserrat', 'Pacifico', 'Oswald', 'Caveat', 'Bebas Neue',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(stickerEditorProvider).activeLayer;
    if (layer == null) return const SizedBox.shrink();
    final notifier = ref.read(stickerEditorProvider.notifier);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          // Color swatch — opens ColorPickerSheet
          GestureDetector(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const ColorPickerSheet(),
            ),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: layer.color,
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: layer.color.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Font pills
          ..._fonts.map((font) {
            final isActive = layer.fontFamily == font ||
                (font == 'Roboto' && layer.fontFamily.isEmpty);
            return GestureDetector(
              onTap: () => notifier.updateLayer(
                layer.id,
                layer.copyWith(fontFamily: font),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isActive ? SeeUColors.accent : c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  font,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : c.ink2,
                  ),
                ),
              ),
            );
          }),
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
  final bool active;
  final bool enabled;
  final SeeUThemeColors c;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.c,
    required this.onTap,
    this.badge,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color boxColor = (active && enabled) ? c.accentSoft : c.surface2;
    final Color iconColor = !enabled ? c.ink4 : active ? SeeUColors.accent : c.ink2;
    final Color labelColor = !enabled ? c.ink4 : active ? SeeUColors.accent : c.ink2;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ),
              if (badge != null)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
