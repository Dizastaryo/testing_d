import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetHandle(c: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Шрифт',
              style: SeeUTypography.subtitle.copyWith(color: c.ink),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              itemCount: kStickerFonts.length,
              itemBuilder: (ctx, i) {
                final font = kStickerFonts[i];
                final isActive = currentFont == font;
                return _FontTile(
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
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  final String font;
  final bool isActive;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _FontTile({
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
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            Expanded(
              child: Text(
                font,
                style: _previewStyle(font).copyWith(
                  fontSize: 20,
                  color: isActive ? SeeUColors.accent : c.ink,
                ),
              ),
            ),
            if (isActive)
              Icon(
                PhosphorIconsRegular.checkCircle,
                color: SeeUColors.accent,
                size: 20,
              ),
          ],
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
