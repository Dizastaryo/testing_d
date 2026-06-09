import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/sticker_provider.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class EmojiStickerPanel extends ConsumerStatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<String> onStickerSelected;
  final VoidCallback onCreateSticker;
  /// When true: встроен в Column (нет handle, нет скруглений сверху, фикс. высота 300).
  final bool inline;

  const EmojiStickerPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    required this.onCreateSticker,
    this.inline = false,
  });

  @override
  ConsumerState<EmojiStickerPanel> createState() => _EmojiStickerPanelState();
}

class _EmojiStickerPanelState extends ConsumerState<EmojiStickerPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SeeUThemeColors c = context.seeuColors;
    return Container(
      height: widget.inline ? 300 : 440,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: widget.inline
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Column(
        children: [
          // Handle — только в modal режиме
          if (!widget.inline)
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
          if (widget.inline) const SizedBox(height: 8),
          // Tab chips
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final idx = _tabController.index;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    _PanelTabChip(
                      label: 'Эмодзи',
                      active: idx == 0,
                      c: c,
                      onTap: () => _tabController.animateTo(0),
                    ),
                    const SizedBox(width: 8),
                    _PanelTabChip(
                      label: 'Стикеры',
                      active: idx == 1,
                      c: c,
                      onTap: () => _tabController.animateTo(1),
                    ),
                    const Spacer(),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EmojiTab(onSelected: widget.onEmojiSelected),
                _StickerTab(
                  onSelected: widget.onStickerSelected,
                  onCreate: widget.onCreateSticker,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji tab — полный набор Unicode через emoji_picker_flutter
// ---------------------------------------------------------------------------

class _EmojiTab extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _EmojiTab({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return EmojiPicker(
      onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
      config: Config(
        checkPlatformCompatibility: true,
        emojiViewConfig: EmojiViewConfig(
          columns: 8,
          emojiSizeMax: 32,
          verticalSpacing: 0,
          horizontalSpacing: 0,
          gridPadding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: c.surface,
          buttonMode: ButtonMode.MATERIAL,
          noRecents: Text(
            'Нет недавних',
            style: TextStyle(fontSize: 14, color: c.ink3),
            textAlign: TextAlign.center,
          ),
          recentsLimit: 30,
        ),
        categoryViewConfig: CategoryViewConfig(
          initCategory: Category.RECENT,
          indicatorColor: SeeUColors.accent,
          iconColor: c.ink3,
          iconColorSelected: SeeUColors.accent,
          backgroundColor: isDark ? c.surface : const Color(0xFFF7F7F7),
          tabIndicatorAnimDuration: const Duration(milliseconds: 150),
          dividerColor: Colors.transparent,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          enabled: true,
          showBackspaceButton: false,
          showSearchViewButton: true,
          backgroundColor: c.surface,
          buttonColor: c.surface,
          buttonIconColor: c.ink3,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: c.surface,
          buttonIconColor: c.ink3,
          hintText: 'Поиск эмодзи...',
          hintTextStyle: TextStyle(fontSize: 14, color: c.ink3),
        ),
        skinToneConfig: SkinToneConfig(
          enabled: true,
          dialogBackgroundColor: c.surface,
          indicatorColor: c.ink3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticker tab
// ---------------------------------------------------------------------------

class _StickerTab extends ConsumerWidget {
  final ValueChanged<String> onSelected;
  final VoidCallback onCreate;

  const _StickerTab({required this.onSelected, required this.onCreate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SeeUThemeColors c = context.seeuColors;
    final stickersAsync = ref.watch(stickerListProvider);

    return stickersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text('Ошибка загрузки',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      ),
      data: (stickers) {
        return Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: stickers.length + 1,
                itemBuilder: (context, i) {
                  // First cell = "create" button
                  if (i == 0) {
                    return GestureDetector(
                      onTap: onCreate,
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(SeeURadii.medium),
                          border: Border.all(
                            color: SeeUColors.accent.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsRegular.plus,
                              size: 22,
                              color: SeeUColors.accent,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Создать',
                              style: SeeUTypography.micro.copyWith(
                                color: SeeUColors.accent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final sticker = stickers[i - 1];
                  final absUrl = AppConfig.absUrl(sticker.url);

                  return GestureDetector(
                    onTap: () => onSelected(sticker.url),
                    onLongPress: () => _confirmDelete(context, ref, sticker),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: absUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) => Icon(
                          PhosphorIconsRegular.smiley,
                          size: 32,
                          color: c.ink3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (stickers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.smiley,
                      size: 40,
                      color: c.ink3,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Нет стикеров\nНажмите + чтобы создать первый',
                      textAlign: TextAlign.center,
                      style: SeeUTypography.caption.copyWith(color: c.ink3),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref, StickerModel sticker) {
    final SeeUThemeColors c = ctx.seeuColors;
    final ValueNotifier<bool> isDeleting = ValueNotifier<bool>(false);
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isDeleting,
              builder: (context, deleting, child) {
                return ListTile(
                  enabled: !deleting,
                  leading: deleting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          PhosphorIconsRegular.trash,
                          color: Colors.redAccent,
                        ),
                  title: const Text('Удалить стикер'),
                  onTap: deleting
                      ? null
                      : () async {
                          isDeleting.value = true;
                          try {
                            await ref
                                .read(stickerListProvider.notifier)
                                .deleteSticker(sticker.id);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          } catch (_) {
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Не удалось удалить стикер'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(isDeleting.dispose);
  }
}

// ---------------------------------------------------------------------------
// Panel tab chip
// ---------------------------------------------------------------------------

class _PanelTabChip extends StatelessWidget {
  final String label;
  final bool active;
  final SeeUThemeColors c;
  final VoidCallback onTap;

  const _PanelTabChip({
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
          color: active ? c.ink : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: active ? c.ink : c.line, width: 0.5),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: active ? c.bg : c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
