import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../models/text_layer.dart';
import '../providers/sticker_editor_provider.dart';

// ─── Цветовая палитра ────────────────────────────────────────────

const List<Color> _kPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF5A3C), // accent orange
  Color(0xFFFF3B30), // red
  Color(0xFFFF9F0A), // orange
  Color(0xFFFFD60A), // yellow
  Color(0xFF34C759), // green
  Color(0xFF00C7BE), // teal
  Color(0xFF007AFF), // blue
  Color(0xFF5856D6), // purple
  Color(0xFFFF2D55), // pink
  Color(0xFF8E8E93), // gray
];

// ─── Основная шторка ─────────────────────────────────────────────

class ColorPickerSheet extends ConsumerStatefulWidget {
  const ColorPickerSheet({super.key});

  @override
  ConsumerState<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends ConsumerState<ColorPickerSheet> {
  late final TextEditingController _hexCtrl;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    final color =
        ref.read(stickerEditorProvider).activeLayer?.color ?? Colors.white;
    _hexCtrl = TextEditingController(text: _toHex(color));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _toHex(Color c) {
    final argb = c.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _fromHex(String hex) {
    final h = hex.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final r = int.tryParse(h.substring(0, 2), radix: 16);
    final g = int.tryParse(h.substring(2, 4), radix: 16);
    final b = int.tryParse(h.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(255, r, g, b);
  }

  void _apply(TextLayer Function(TextLayer) updater) {
    final layer = ref.read(stickerEditorProvider).activeLayer;
    if (layer == null) return;
    ref.read(stickerEditorProvider.notifier).updateLayer(layer.id, updater(layer));
  }

  void _applyLive(TextLayer Function(TextLayer) updater) {
    final layer = ref.read(stickerEditorProvider).activeLayer;
    if (layer == null) return;
    ref.read(stickerEditorProvider.notifier).updateLayerLive(layer.id, updater(layer));
  }

  void _commit() => ref.read(stickerEditorProvider.notifier).commitGesture();

  void _applyTextColor(Color color) {
    _apply((l) => l.copyWith(color: color));
    setState(() {
      _hexCtrl.text = _toHex(color);
      _hexError = false;
    });
  }

  void _onHexSubmit() {
    final color = _fromHex(_hexCtrl.text);
    if (color != null) {
      _apply((l) => l.copyWith(color: color));
      setState(() => _hexError = false);
    } else {
      setState(() => _hexError = true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final layer = ref.watch(stickerEditorProvider).activeLayer;

    if (layer == null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('Выберите слой', style: SeeUTypography.body.copyWith(color: c.ink3)),
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Handle(c: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Цвет и стиль',
              style: SeeUTypography.subtitle.copyWith(color: c.ink),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Цвет текста ─────────────────────────────
                  _SectionLabel('Цвет текста', c),
                  _ColorPaletteRow(
                    colors: _kPalette,
                    selected: layer.color,
                    onSelect: _applyTextColor,
                  ),
                  const SizedBox(height: 8),
                  _HexInput(
                    controller: _hexCtrl,
                    hasError: _hexError,
                    onSubmit: _onHexSubmit,
                    c: c,
                  ),

                  const SizedBox(height: 16),

                  // ── Стиль ────────────────────────────────────
                  _SectionLabel('Стиль', c),
                  _StyleToggles(layer: layer, onApply: _apply),

                  const SizedBox(height: 16),

                  // ── Прозрачность ─────────────────────────────
                  _SectionLabel('Прозрачность', c),
                  Slider(
                    value: layer.opacity,
                    min: 0.1,
                    max: 1.0,
                    activeColor: SeeUColors.accent,
                    inactiveColor: c.line,
                    onChanged: (v) => _applyLive((l) => l.copyWith(opacity: v)),
                    onChangeEnd: (_) => _commit(),
                  ),

                  const SizedBox(height: 16),

                  // ── Обводка ──────────────────────────────────
                  _SectionLabel('Обводка', c),
                  _StrokeSection(layer: layer, onApply: _apply, onLive: _applyLive, onCommit: _commit, c: c),

                  const SizedBox(height: 16),

                  // ── Тень ─────────────────────────────────────
                  _SectionLabel('Тень', c),
                  _ShadowSection(layer: layer, onApply: _apply, onLive: _applyLive, onCommit: _commit, c: c),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ─── Секция: Обводка ──────────────────────────────────────────────

class _StrokeSection extends StatelessWidget {
  final TextLayer layer;
  final void Function(TextLayer Function(TextLayer)) onApply;
  final void Function(TextLayer Function(TextLayer)) onLive;
  final VoidCallback onCommit;
  final SeeUThemeColors c;

  const _StrokeSection({
    required this.layer,
    required this.onApply,
    required this.onLive,
    required this.onCommit,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Вкл', style: SeeUTypography.body.copyWith(color: c.ink2)),
            const SizedBox(width: 8),
            Switch(
              value: layer.hasStroke,
              activeThumbColor: SeeUColors.accent,
              onChanged: (v) => onApply((l) => l.copyWith(hasStroke: v)),
            ),
          ],
        ),
        if (layer.hasStroke) ...[
          const SizedBox(height: 6),
          _ColorPaletteRow(
            colors: _kPalette,
            selected: layer.strokeColor,
            onSelect: (color) => onApply((l) => l.copyWith(strokeColor: color)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Толщина ${layer.strokeWidth.round()}px',
                style: SeeUTypography.caption.copyWith(color: c.ink3),
              ),
            ],
          ),
          Slider(
            value: layer.strokeWidth,
            min: 1,
            max: 8,
            divisions: 7,
            activeColor: SeeUColors.accent,
            inactiveColor: c.line,
            onChanged: (v) => onLive((l) => l.copyWith(strokeWidth: v)),
            onChangeEnd: (_) => onCommit(),
          ),
        ],
      ],
    );
  }
}

// ─── Секция: Тень ─────────────────────────────────────────────────

class _ShadowSection extends StatelessWidget {
  final TextLayer layer;
  final void Function(TextLayer Function(TextLayer)) onApply;
  final void Function(TextLayer Function(TextLayer)) onLive;
  final VoidCallback onCommit;
  final SeeUThemeColors c;

  const _ShadowSection({
    required this.layer,
    required this.onApply,
    required this.onLive,
    required this.onCommit,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Вкл', style: SeeUTypography.body.copyWith(color: c.ink2)),
            const SizedBox(width: 8),
            Switch(
              value: layer.hasShadow,
              activeThumbColor: SeeUColors.accent,
              onChanged: (v) => onApply((l) => l.copyWith(hasShadow: v)),
            ),
          ],
        ),
        if (layer.hasShadow) ...[
          const SizedBox(height: 6),
          _ColorPaletteRow(
            colors: _kPalette,
            selected: layer.shadowColor,
            onSelect: (color) => onApply((l) => l.copyWith(shadowColor: color)),
          ),
          const SizedBox(height: 4),
          Text(
            'Размытие ${layer.shadowBlur.round()}px',
            style: SeeUTypography.caption.copyWith(color: c.ink3),
          ),
          Slider(
            value: layer.shadowBlur,
            min: 0,
            max: 20,
            activeColor: SeeUColors.accent,
            inactiveColor: c.line,
            onChanged: (v) => onLive((l) => l.copyWith(shadowBlur: v)),
            onChangeEnd: (_) => onCommit(),
          ),
        ],
      ],
    );
  }
}

// ─── Кнопки стиля (Bold / Italic / Underline) ─────────────────────

class _StyleToggles extends StatelessWidget {
  final TextLayer layer;
  final void Function(TextLayer Function(TextLayer)) onApply;

  const _StyleToggles({required this.layer, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Row(
      children: [
        _StyleChip(
          label: 'B',
          bold: true,
          active: layer.bold,
          onTap: () => onApply((l) => l.copyWith(bold: !l.bold)),
          c: c,
        ),
        const SizedBox(width: 8),
        _StyleChip(
          label: 'I',
          italic: true,
          active: layer.italic,
          onTap: () => onApply((l) => l.copyWith(italic: !l.italic)),
          c: c,
        ),
        const SizedBox(width: 8),
        _StyleChip(
          label: 'U',
          underline: true,
          active: layer.underline,
          onTap: () => onApply((l) => l.copyWith(underline: !l.underline)),
          c: c,
        ),
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool active;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _StyleChip({
    required this.label,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    required this.active,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : c.ink2,
              fontSize: 18,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : TextDecoration.none,
              decorationColor: active ? Colors.white : c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Палитра цветов ───────────────────────────────────────────────

class _ColorPaletteRow extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final void Function(Color) onSelect;

  const _ColorPaletteRow({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected =
            color.toARGB32() == selected.toARGB32();
        return GestureDetector(
          onTap: () => onSelect(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? SeeUColors.accent : Colors.white24,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    PhosphorIconsBold.check,
                    size: 14,
                    color: color.toARGB32() == Colors.white.toARGB32()
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ─── HEX-поле ────────────────────────────────────────────────────

class _HexInput extends StatelessWidget {
  final TextEditingController controller;
  final bool hasError;
  final VoidCallback onSubmit;
  final SeeUThemeColors c;

  const _HexInput({
    required this.controller,
    required this.hasError,
    required this.onSubmit,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: SeeUTypography.body.copyWith(color: c.ink),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(7),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: '#FFFFFF',
              hintStyle: SeeUTypography.body.copyWith(color: c.ink4),
              errorText: hasError ? 'Неверный HEX' : null,
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSubmit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
            child: Text(
              'OK',
              style: SeeUTypography.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Мелкие переиспользуемые виджеты ─────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final SeeUThemeColors c;
  const _SectionLabel(this.text, this.c);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: SeeUTypography.caption.copyWith(
          color: c.ink3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

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
