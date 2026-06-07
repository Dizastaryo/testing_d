import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/sticker_provider.dart';

// ---------------------------------------------------------------------------
// Emoji category data
// ---------------------------------------------------------------------------
const _emojiCategories = {
  'Эмоции': [
    '😀', '😂', '🥲', '😍', '😎', '😭', '😡', '🤔', '🤩', '🥳',
    '😴', '🥺', '😱', '😏', '🤗', '😐', '🫠', '🤭', '🫡', '😇',
    '🤪', '😋', '🥴', '😤', '🫢', '😬', '🙃', '😑', '😶',
    '🥰', '😘', '😜', '😅', '😉', '😊', '🤣', '☺️', '😌', '😔',
    '🤯', '🤠', '🤓', '🤫', '😶‍🌫️',
  ],
  'Сердечки': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💖',
    '💯', '✨', '💕', '💞', '💓', '💗', '❣️', '💝', '🫶',
  ],
  'Жесты': [
    '👍', '👎', '👏', '🙌', '🙏', '💪', '🤝', '👌', '✌️', '🤘',
    '🫶', '🤜', '🤛', '👊', '✊', '🤙', '🫰', '🤞', '🫵',
  ],
  'Прочее': [
    '🔥', '🎉', '🚀', '⭐', '⚡', '💀', '👀', '🎯', '💊', '🏆',
    '🎁', '🫧', '🌈', '🍕', '🍔', '🎶', '🤡', '👾', '🧠',
  ],
};

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class EmojiStickerPanel extends ConsumerStatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<String> onStickerSelected;
  final VoidCallback onCreateSticker;

  const EmojiStickerPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    required this.onCreateSticker,
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
      height: 360,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
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
          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: SeeUColors.accent,
            unselectedLabelColor: c.ink3,
            indicatorColor: SeeUColors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Эмодзи'),
              Tab(text: 'Стикеры'),
            ],
          ),
          const SizedBox(height: 4),
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
// Emoji tab
// ---------------------------------------------------------------------------

class _EmojiTab extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _EmojiTab({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final SeeUThemeColors c = context.seeuColors;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: _emojiCategories.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.key,
                style: SeeUTypography.caption.copyWith(
                  color: c.ink3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: entry.value
                  .map((emoji) => _EmojiTapButton(
                        emoji: emoji,
                        onTap: () => onSelected(emoji),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated emoji tap button
// ---------------------------------------------------------------------------

class _EmojiTapButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiTapButton({required this.emoji, required this.onTap});

  @override
  State<_EmojiTapButton> createState() => _EmojiTapButtonState();
}

class _EmojiTapButtonState extends State<_EmojiTapButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        widget.onTap();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) setState(() => _pressed = false);
        });
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 1.3 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.small),
          ),
          alignment: Alignment.center,
          child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
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
