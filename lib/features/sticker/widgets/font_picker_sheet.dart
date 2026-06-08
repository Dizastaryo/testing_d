import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/design.dart';
import '../models/text_layer.dart';
import '../providers/sticker_editor_provider.dart';

class FontPickerSheet extends ConsumerWidget {
  const FontPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final activeLayer = ref.watch(stickerEditorProvider).activeLayer;
    final notifier = ref.read(stickerEditorProvider.notifier);
    final currentFont = activeLayer?.fontFamily ?? 'Roboto';

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SeeURadii.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetHandle(c: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'Шрифт',
              style: SeeUTypography.subtitle.copyWith(color: c.ink),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: kStickerFonts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final font = kStickerFonts[i];
                final isActive = currentFont == font;
                return _FontChip(
                  font: font,
                  isActive: isActive,
                  onTap: () {
                    if (activeLayer != null) {
                      notifier.updateLayer(
                        activeLayer.id,
                        activeLayer.copyWith(fontFamily: font),
                      );
                    }
                    Navigator.pop(context);
                  },
                  c: c,
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  final String font;
  final bool isActive;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _FontChip({
    required this.font,
    required this.isActive,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 52),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isActive ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Center(
          child: Text(
            'Aa',
            style: _previewStyle(font).copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : c.ink2,
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _previewStyle(String fontFamily) {
    const base = TextStyle(fontWeight: FontWeight.w500);
    return switch (fontFamily) {
      'Pacifico'   => GoogleFonts.pacifico(textStyle: base),
      'Bebas Neue' => GoogleFonts.bebasNeue(textStyle: base),
      'Oswald'     => GoogleFonts.oswald(textStyle: base),
      'Caveat'     => GoogleFonts.caveat(textStyle: base),
      'Montserrat' => GoogleFonts.montserrat(textStyle: base),
      _            => GoogleFonts.roboto(textStyle: base),
    };
  }
}

// ─── Shared handle ────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  final SeeUThemeColors c;
  const _SheetHandle({required this.c});

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
