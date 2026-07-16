import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/models/playlist.dart';
import '../../core/providers/audio_provider.dart';
import '../../core/providers/playlist_provider.dart';
import 'audio_design.dart';
import 'music_search_screen.dart' show AudioErrorState;
import 'widgets/moderation_card.dart';
import 'widgets/playlist_cover.dart';
import 'widgets/track_row.dart';

/// «Моё» — всё, что принадлежит человеку: плейлисты, сохранённое, история и
/// его собственные загрузки. Главная отвечает на «что послушать сейчас», а
/// этот раздел — на «где мои вещи».
class MyAudioScreen extends ConsumerStatefulWidget {
  /// С какого сегмента открыть (?tab=uploads — из формы загрузки).
  final String initialTab;

  const MyAudioScreen({super.key, this.initialTab = ''});

  @override
  ConsumerState<MyAudioScreen> createState() => _MyAudioScreenState();
}

class _MyAudioScreenState extends ConsumerState<MyAudioScreen> {
  static const _tabs = ['playlists', 'saved', 'recent', 'uploads'];
  static const _labels = ['Плейлисты', 'Сохранённое', 'Недавнее', 'Загрузки'];

  late int _tab = () {
    final i = _tabs.indexOf(widget.initialTab);
    return i < 0 ? 0 : i;
  }();

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AudioMainBar(title: 'Моё'),
            const SizedBox(height: 14),
            _segments(c),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _segments(SeeUThemeColors c) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final active = i == _tab;
          return Tappable.scaled(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _tab = i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? c.ink : c.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? c.ink : c.line),
              ),
              child: Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? c.bg : c.ink2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() => switch (_tabs[_tab]) {
        'saved' => const _SavedTab(),
        'recent' => const _RecentTab(),
        'uploads' => const _UploadsTab(),
        _ => const _PlaylistsTab(),
      };
}

// ─── Плейлисты ──────────────────────────────────────────────────────────────

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(myPlaylistsProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.only(top: 20), child: AudioListSkeleton(rows: 6)),
      error: (_, __) =>
          AudioErrorState(onRetry: () => ref.read(myPlaylistsProvider.notifier).load()),
      data: (lists) => ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + context.bottomBarInset),
        children: [
          Tappable.scaled(
            onTap: () => _createPlaylist(context, ref),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.4),
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(PhosphorIconsBold.plus,
                      size: 15, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Новый плейлист',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AudioColors.kicker(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                'Плейлист — это твоя подборка. Собери первую.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.78,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final p in lists) _PlaylistTile(playlist: p),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    try {
      await _createPlaylistFlow(context, ref, ctrl);
    } finally {
      // Контроллер создаётся вне State — без явного dispose утекал на каждый
      // вызов листа.
      ctrl.dispose();
    }
  }

  Future<void> _createPlaylistFlow(
      BuildContext context, WidgetRef ref, TextEditingController ctrl) async {
    final ok = await showSeeUBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              22, 4, 22, MediaQuery.viewInsetsOf(ctx).bottom + 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Новый плейлист',
                style:
                    SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 14),
              SeeUInput(
                controller: ctrl,
                hintText: 'Например, «Для дороги»',
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SeeUButton(
                  label: 'Создать',
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    final created = await ref.read(myPlaylistsProvider.notifier).create(name);
    // Раньше провал сервера молча проглатывался — лист закрывался, а плейлист
    // не появлялся, и юзеру ничего не сообщалось.
    if (created == null && context.mounted) {
      showSeeUSnackBar(context, 'Не удалось создать плейлист',
          tone: SeeUTone.danger);
    }
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: PlaylistCover(playlist: playlist, radius: 16),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
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
            tracksCountLabel(playlist.tracksCount),
            style: TextStyle(fontSize: 11.5, color: c.ink3),
          ),
        ],
      ),
    );
  }
}

// ─── Сохранённое ────────────────────────────────────────────────────────────

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(savedTracksProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.only(top: 20), child: AudioListSkeleton(rows: 6)),
      error: (_, __) =>
          AudioErrorState(onRetry: () => ref.invalidate(savedTracksProvider)),
      data: (tracks) {
        if (tracks.isEmpty) {
          return _empty(
            context,
            icon: PhosphorIcons.bookmarkSimple(),
            title: 'Пока ничего не сохранено',
            subtitle:
                'Жми закладку на карточке трека — он ляжет сюда и будет под рукой',
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + context.bottomBarInset),
          children: [
            Row(
              children: [
                Text(
                  '${tracks.length} ${tracksWord(tracks.length)}',
                  style: TextStyle(fontSize: 13, color: c.ink3),
                ),
                const Spacer(),
                Tappable.scaled(
                  onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
                        track: tracks.first,
                        queue: tracks,
                        index: 0,
                        source: 'saved',
                      ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.play,
                            size: 13, color: Colors.white),
                        SizedBox(width: 7),
                        Text(
                          'Слушать всё',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < tracks.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: TrackRow(
                  track: tracks[i],
                  queue: tracks,
                  index: i,
                  source: 'saved',
                  trailing: TrackRowTrailing.saved,
                  // Снятие сохранения обновляет список — трек уходит из «Сохранённого».
                  onChanged: () => ref.invalidate(savedTracksProvider),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Недавнее ───────────────────────────────────────────────────────────────

class _RecentTab extends ConsumerWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(recentTracksProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.only(top: 20), child: AudioListSkeleton(rows: 6)),
      error: (_, __) =>
          AudioErrorState(onRetry: () => ref.invalidate(recentTracksProvider)),
      data: (tracks) {
        if (tracks.isEmpty) {
          return _empty(
            context,
            icon: PhosphorIcons.clockCounterClockwise(),
            title: 'История пуста',
            subtitle: 'Всё, что послушаешь, соберётся здесь по дням',
          );
        }

        // Группируем по дням: «Сегодня / Вчера / На неделе / Раньше».
        final groups = <String, List<AudioTrack>>{};
        for (final t in tracks) {
          groups.putIfAbsent(_groupOf(t.playedAt), () => []).add(t);
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + context.bottomBarInset),
          children: [
            for (final entry in groups.entries) ...[
              Text(
                entry.key.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: c.ink3,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < entry.value.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: TrackRow(
                    track: entry.value[i],
                    queue: tracks,
                    index: tracks.indexOf(entry.value[i]),
                    source: 'recent',
                    trailing: TrackRowTrailing.time,
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }

  static String _groupOf(DateTime? at) {
    if (at == null) return 'Раньше';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (diff < 7) return 'На неделе';
    return 'Раньше';
  }
}

// ─── Мои загрузки + модерация ───────────────────────────────────────────────

class _UploadsTab extends ConsumerStatefulWidget {
  const _UploadsTab();

  @override
  ConsumerState<_UploadsTab> createState() => _UploadsTabState();
}

class _UploadsTabState extends ConsumerState<_UploadsTab> {
  /// '' — все, 'pending', 'rejected'.
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(myTracksProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.only(top: 20), child: AudioListSkeleton(rows: 6)),
      error: (_, __) =>
          AudioErrorState(onRetry: () => ref.invalidate(myTracksProvider)),
      data: (all) {
        if (all.isEmpty) {
          return _empty(
            context,
            icon: PhosphorIcons.uploadSimple(),
            title: 'Ты ещё ничего не загружал',
            subtitle: 'Загрузи трек — он пройдёт модерацию и станет доступен всем',
            action: 'Загрузить трек',
            onAction: () => context.push('/music/upload'),
          );
        }

        final pending = all.where((t) => t.status == 'pending').length;
        final rejected = all.where((t) => t.status == 'rejected').length;
        final shown = _filter.isEmpty
            ? all
            : all.where((t) => t.status == _filter).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + context.bottomBarInset),
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(c, '', 'Все · ${all.length}'),
                        if (pending > 0) ...[
                          const SizedBox(width: 7),
                          _chip(c, 'pending', 'На проверке · $pending'),
                        ],
                        if (rejected > 0) ...[
                          const SizedBox(width: 7),
                          _chip(c, 'rejected', 'Отклонён · $rejected'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tappable.scaled(
                  onTap: () => context.push('/music/upload'),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.ink,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(PhosphorIconsBold.plus, size: 15, color: c.bg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final t in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ModerationCard(
                  track: t,
                  onChanged: () => ref.invalidate(myTracksProvider),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _chip(SeeUThemeColors c, String id, String label) {
    final active = _filter == id;
    return Tappable.scaled(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filter = id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.ink : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? c.ink : c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? c.bg : c.ink2,
          ),
        ),
      ),
    );
  }
}

// ─── Общее пустое состояние ─────────────────────────────────────────────────

Widget _empty(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  String? action,
  VoidCallback? onAction,
}) {
  final c = context.seeuColors;
  return ListView(
    padding: const EdgeInsets.fromLTRB(44, 80, 44, 0),
    children: [
      Center(
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeeUColors.accent.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 38, color: SeeUColors.accent),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        title,
        textAlign: TextAlign.center,
        style: SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
      ),
      if (action != null) ...[
        const SizedBox(height: 22),
        Center(
          child: Tappable.scaled(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.plus,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    action,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

String tracksWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return 'треков';
  if (m10 == 1) return 'трек';
  if (m10 >= 2 && m10 <= 4) return 'трека';
  return 'треков';
}

String tracksCountLabel(int n) => n == 0 ? 'Пусто' : '$n ${tracksWord(n)}';
