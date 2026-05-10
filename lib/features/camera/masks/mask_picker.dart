import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';
import 'ai_mask_models.dart';
import 'ai_mask_prompt_sheet.dart';
import 'ai_masks_provider.dart';
import 'image_mask_painter.dart';
import 'mask_catalog.dart';

/// Горизонтальная плашка масок над bottom-controls.
///
/// Layout: «Без» → 8 встроенных → «✨ AI» (открывает prompt-sheet) → история
/// AI-масок юзера (тайтлы — usage prompt'а, аватарка — превью PNG).
class MaskPicker extends ConsumerWidget {
  final MaskDescriptor? selected;
  final ValueChanged<MaskDescriptor?> onChanged;

  const MaskPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiAsync = ref.watch(aiMasksProvider);
    final aiMasks = aiAsync.value ?? const [];

    // Структура items: 1 (none) + 8 builtin + 1 (AI generate button) + history
    final builtinCount = MaskCatalog.all.length;
    final aiCount = aiMasks.length;
    final totalCount = 1 + builtinCount + 1 + aiCount;

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            // «Без маски»
            return _MaskBubble(
              isSelected: selected == null,
              label: 'Без',
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(null);
              },
              child: Icon(
                PhosphorIcons.x(),
                color: Colors.white.withValues(alpha: 0.85),
                size: 22,
              ),
            );
          }
          if (i < 1 + builtinCount) {
            final m = MaskCatalog.all[i - 1];
            final isSelected = selected?.id == m.id;
            return _MaskBubble(
              isSelected: isSelected,
              label: m.label,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(m);
              },
              child: Icon(m.previewIcon, color: Colors.white, size: 22),
            );
          }
          if (i == 1 + builtinCount) {
            // «✨ AI» — генерация новой маски
            return _MaskBubble(
              isSelected: false,
              label: 'AI ✨',
              gradient: SeeUGradients.heroOrange,
              onTap: () async {
                HapticFeedback.mediumImpact();
                final created = await showAIMaskPromptSheet(context);
                if (created != null) {
                  // Применяем сразу созданную маску.
                  onChanged(_aiToDescriptor(created));
                }
              },
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 22),
            );
          }
          // История AI-масок
          final aiIdx = i - 1 - builtinCount - 1;
          final m = aiMasks[aiIdx];
          final descriptor = _aiToDescriptor(m);
          final isSelected = selected?.id == descriptor.id;
          return GestureDetector(
            onLongPress: () => _showAIMaskMenu(context, ref, m),
            child: _MaskBubble(
              isSelected: isSelected,
              label: _shortenPrompt(m.prompt),
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(descriptor);
              },
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: AppConfig.apiOrigin + m.fileUrl,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  MaskDescriptor _aiToDescriptor(AIMask m) {
    return aiMaskDescriptor(
      id: m.id,
      label: _shortenPrompt(m.prompt),
      imageUrl: AppConfig.apiOrigin + m.fileUrl,
    );
  }

  String _shortenPrompt(String p) {
    final t = p.trim();
    if (t.length <= 14) return t;
    return '${t.substring(0, 12)}…';
  }

  void _showAIMaskMenu(BuildContext context, WidgetRef ref, AIMask m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF0181412),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: Text(m.prompt,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                  'Создано ${m.createdAt.toLocal().toString().split('.')[0]}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: SeeUColors.error),
              title: const Text('Удалить',
                  style: TextStyle(color: SeeUColors.error)),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  await ref.read(aiMasksProvider.notifier).delete(m.id);
                  HapticFeedback.lightImpact();
                } catch (_) {}
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskBubble extends StatelessWidget {
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final Gradient? gradient;

  const _MaskBubble({
    required this.isSelected,
    required this.label,
    required this.onTap,
    required this.child,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: SeeUMotion.quick,
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              color:
                  gradient == null ? Colors.white.withValues(alpha: 0.15) : null,
              border: Border.all(
                color: isSelected
                    ? SeeUColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Center(child: child),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? SeeUColors.accent
                    : Colors.white.withValues(alpha: 0.75),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
