import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/config/app_config.dart';
import '../core/design/design.dart';
import '../core/providers/gif_provider.dart';

/// Category chips + grid over the shared GIF library — used inline by
/// `EmojiStickerPanel`'s GIF tab (chat/rooms) and inside [showGifPickerSheet]
/// (comments), so both surfaces browse the same R2-backed library.
class GifPickerGrid extends ConsumerStatefulWidget {
  final ValueChanged<String> onSelected;

  const GifPickerGrid({super.key, required this.onSelected});

  @override
  ConsumerState<GifPickerGrid> createState() => _GifPickerGridState();
}

class _GifPickerGridState extends ConsumerState<GifPickerGrid> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final SeeUThemeColors c = context.seeuColors;
    final categoriesAsync = ref.watch(gifCategoryProvider);

    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text('Ошибка загрузки',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      ),
      data: (categories) {
        if (categories.isEmpty) {
          return Center(
            child: Text('Нет доступных категорий',
                style: SeeUTypography.body.copyWith(color: c.ink3)),
          );
        }
        final category = _category ?? categories.first;
        return Column(
          children: [
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  return _GifCategoryChip(
                    label: cat,
                    active: cat == category,
                    c: c,
                    onTap: () => setState(() => _category = cat),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _GifGrid(category: category, onSelected: widget.onSelected)),
          ],
        );
      },
    );
  }
}

class _GifGrid extends ConsumerWidget {
  final String category;
  final ValueChanged<String> onSelected;

  const _GifGrid({required this.category, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SeeUThemeColors c = context.seeuColors;
    final gifsAsync = ref.watch(gifListProvider(category));

    return gifsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text('Ошибка загрузки',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      ),
      data: (gifs) {
        if (gifs.isEmpty) {
          return Center(
            child: Text('Нет гифок в этой категории',
                style: SeeUTypography.caption.copyWith(color: c.ink3)),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: gifs.length,
          itemBuilder: (context, i) {
            final gif = gifs[i];
            return GestureDetector(
              onTap: () => onSelected(gif.fullUrl),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: AppConfig.absUrl(gif.previewUrl),
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.surface2),
                  errorWidget: (_, __, ___) => Icon(
                    PhosphorIconsRegular.image,
                    size: 32,
                    color: c.ink3,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GifCategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final SeeUThemeColors c;
  final VoidCallback onTap;

  const _GifCategoryChip({
    required this.label,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: active
                ? SeeUColors.accent.withValues(alpha: 0.5)
                : c.line,
            width: active ? 0.8 : 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: SeeUTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? SeeUColors.accent : c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [GifPickerGrid] in a bottom sheet — for composer surfaces (comments)
/// that don't already embed a full emoji/sticker/GIF tabbed panel.
Future<void> showGifPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onSelected,
}) {
  return showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final c = sheetCtx.seeuColors;
      return SizedBox(
        height: 420,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Text('GIF',
                      style: SeeUTypography.subtitle.copyWith(color: c.ink)),
                ],
              ),
            ),
            Expanded(
              child: GifPickerGrid(
                onSelected: (url) {
                  Navigator.of(sheetCtx).pop();
                  onSelected(url);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
