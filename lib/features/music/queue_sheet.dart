import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';

/// Bottom sheet showing the live play queue. The current track is highlighted;
/// tap any track to jump to it; drag the handle to reorder upcoming tracks.
void showQueueSheet(BuildContext context) {
  showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final state = ref.watch(miniPlayerProvider);
    final notifier = ref.read(miniPlayerProvider.notifier);
    final queue = state.queue;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.listBullets(), color: SeeUColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('ОЧЕРЕДЬ',
                            style: SeeUTypography.kicker
                                .copyWith(color: c.ink3)),
                        const SizedBox(height: 2),
                        Text('Играет сейчас',
                            style: SeeUTypography.displayS
                                .copyWith(color: c.ink)),
                      ],
                    ),
                  ),
                  Text('${queue.length} треков',
                      style: SeeUTypography.caption.copyWith(color: c.ink3)),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            Flexible(
              child: queue.isEmpty
                  ? const SeeUEmptyState(
                      icon: PhosphorIconsRegular.queue,
                      title: 'Очередь пуста',
                      subtitle:
                          'Добавьте треки — они появятся здесь по порядку',
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: queue.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.selectionClick();
                        notifier.reorderQueue(oldIndex, newIndex);
                      },
                      itemBuilder: (context, i) {
                        final t = queue[i];
                        final isCurrent = i == state.queueIndex;
                        return Container(
                          key: ValueKey(t.id),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: isCurrent
                              ? BoxDecoration(
                                  color: c.accentSoft,
                                  borderRadius: BorderRadius.circular(
                                      SeeURadii.medium),
                                  border: Border.all(
                                    color: SeeUColors.accent
                                        .withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                )
                              : null,
                          child: ListTile(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (isCurrent) {
                                notifier.toggle();
                              } else {
                                notifier.jumpTo(i);
                              }
                              Navigator.of(context).maybePop();
                            },
                            leading: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(SeeURadii.small),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: t.coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: t.coverUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(color: c.surface2),
                                      )
                                    : Container(
                                        color: c.surface2,
                                        child: Icon(
                                            PhosphorIcons.musicNotesSimple(),
                                            color: c.ink3,
                                            size: 18),
                                      ),
                              ),
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isCurrent ? SeeUColors.accent : c.ink,
                              ),
                            ),
                            subtitle: Text(
                              t.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.ink3),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent && state.playing)
                                  Icon(PhosphorIcons.waveform(),
                                      color: SeeUColors.accent, size: 18)
                                else if (isCurrent)
                                  Icon(PhosphorIcons.pause(),
                                      color: SeeUColors.accent, size: 18),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(PhosphorIcons.dotsSixVertical(),
                                        color: c.ink3, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
