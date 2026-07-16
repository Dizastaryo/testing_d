import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import 'audio_design.dart';

/// Очередь: что играет сейчас и что дальше.
///
/// Показываем, **откуда** очередь взялась («Из микса „Твой день“») — иначе
/// непонятно, почему после мема вдруг играет медитация. Порядок меняется
/// перетаскиванием, лишнее убирается крестиком.
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
    final player = ref.watch(miniPlayerProvider);
    final notifier = ref.read(miniPlayerProvider.notifier);

    final current = player.track;
    if (current == null) return const SizedBox.shrink();

    final mode = modeOf(current);
    final upcoming = player.queue
        .asMap()
        .entries
        .where((e) => e.key > player.queueIndex)
        .toList();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Text(
                    'Очередь',
                    style: SeeUTypography.displayS
                        .copyWith(fontSize: 22, color: c.ink),
                  ),
                  const Spacer(),
                  if (upcoming.isNotEmpty)
                    Tappable(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        // Оставляем играющий трек, отрезаем всё, что после.
                        notifier.clearUpcoming();
                      },
                      child: Text(
                        'Очистить',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AudioColors.kicker(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Откуда очередь — иначе непонятно, почему играет именно это.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: mode.soft(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsFill.listPlus, size: 13, color: mode.color),
                    const SizedBox(width: 7),
                    Text(
                      _sourceLabel(player.queueSource),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mode.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'СЕЙЧАС',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: c.ink3,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mode.soft(context),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: mode.color.withValues(alpha: 0.28)),
                ),
                child: Row(
                  children: [
                    TrackCover(track: current, size: 46, radius: 10),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            current.artist.isNotEmpty
                                ? current.artist
                                : formatDuration(current.durationSeconds),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.ink3),
                          ),
                        ],
                      ),
                    ),
                    if (player.playing)
                      NowPlayingBars(color: mode.color, height: 16),
                  ],
                ),
              ),
            ),

            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
                child: Text(
                  'Дальше ничего — это последний трек в очереди.',
                  style: TextStyle(fontSize: 13, color: c.ink3),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                child: Row(
                  children: [
                    Text(
                      'ДАЛЬШЕ · ${upcoming.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: c.ink3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'перетащи ⇅',
                      style: TextStyle(fontSize: 11, color: c.ink4),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  itemCount: upcoming.length,
                  // onReorderItem появился ПОСЛЕ Flutter 3.41.0 — на CI-таргете
                  // (3.41.6) его нет вовсе, есть только onReorder (там он ещё не
                  // deprecated). onReorder компилируется на обеих версиях, поэтому
                  // это верный выбор под сборку. ignore гасит info-предупреждение
                  // о deprecation, которое видит лишь локальный 3.44.
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) {
                    HapticFeedback.selectionClick();
                    // Стандартный onReorder отдаёт СЫРОЙ newIndex (без -1 при
                    // движении вниз) — именно это ждёт reorderQueue, который сам
                    // корректирует (target -= 1 при target > oldIndex). Никакой
                    // ручной компенсации не нужно.
                    final base = player.queueIndex + 1;
                    notifier.reorderQueue(base + oldIndex, base + newIndex);
                  },
                  itemBuilder: (_, i) {
                    final entry = upcoming[i];
                    final t = entry.value;
                    return Padding(
                      key: ValueKey('${t.id}_${entry.key}'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(PhosphorIcons.dotsSixVertical(),
                                  size: 20, color: c.ink4),
                            ),
                          ),
                          Expanded(
                            child: Tappable(
                              onTap: () {
                                notifier.jumpTo(entry.key);
                                Navigator.of(context).pop();
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    TrackCover(track: t, size: 44, radius: 10),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: c.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (t.artist.isNotEmpty) t.artist,
                                              formatDuration(t.durationSeconds),
                                            ]
                                                .where((e) => e.isNotEmpty)
                                                .join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.ink3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Tappable(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              notifier.removeFromQueue(entry.key);
                            },
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(PhosphorIcons.x(),
                                  size: 17, color: c.ink3),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(String src) => switch (src) {
        'daily_mix' => 'Из микса «Твой день»',
        'playlist' => 'Из плейлиста',
        'saved' => 'Из сохранённого',
        'recent' => 'Из недавнего',
        'trending' => 'Из «Набирают»',
        'search' => 'Из поиска',
        'category' => 'Из категории',
        'continue' => 'Из «Продолжить»',
        'moment' => 'Один звук',
        _ => 'Из ленты',
      };
}
