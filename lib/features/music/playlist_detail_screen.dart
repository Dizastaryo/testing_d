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
import 'widgets/playlist_cover.dart';

/// Экран плейлиста. Обложка — мозаика из обложек треков. Пустой плейлист не
/// молчит: сразу даёт кнопку «Добавить треки», а не оставляет человека гадать.
class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(playlistDetailProvider(playlistId));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(
            child: AudioListSkeleton(rows: 6),
          ),
          error: (_, __) => Column(
            children: [
              _bar(context, ref, null),
              Expanded(
                child: AudioErrorState(
                  onRetry: () =>
                      ref.read(playlistDetailProvider(playlistId).notifier).load(),
                ),
              ),
            ],
          ),
          data: (detail) => _body(context, ref, detail),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, PlaylistDetail detail) {
    final c = context.seeuColors;
    final p = detail.playlist;
    final tracks = detail.tracks;

    return ListView(
      padding: EdgeInsets.only(bottom: 24 + context.bottomBarInset),
      children: [
        _bar(context, ref, p),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: PlaylistCover(playlist: p, radius: 18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ПЛЕЙЛИСТ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AudioColors.kicker(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.displayS.copyWith(
                        fontSize: 28,
                        height: 1.02,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tracks.isEmpty
                          ? 'Пока пусто'
                          : '${tracks.length} ${_word(tracks.length)} · '
                              '${_totalTime(tracks)}',
                      style: TextStyle(fontSize: 12.5, color: c.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (tracks.isEmpty)
          _empty(context)
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Tappable.scaled(
                    onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
                          track: tracks.first,
                          queue: tracks,
                          index: 0,
                          source: 'playlist',
                        ),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: SeeUColors.accent.withValues(alpha: 0.55),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsFill.play,
                              size: 15, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Слушать',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _iconButton(
                  c,
                  PhosphorIcons.shuffle(),
                  () async {
                    HapticFeedback.selectionClick();
                    // Играем плейлист в исходном порядке и включаем настоящий
                    // shuffle плеера: тогда его тумблер показывает ВКЛ, а
                    // originalQueue = реальный порядок, и выключение shuffle
                    // корректно его восстанавливает. Раньше очередь тасовалась
                    // вручную, а флаг оставался OFF (рассинхрон тумблера).
                    final notifier = ref.read(miniPlayerProvider.notifier);
                    await notifier.playWithQueue(
                      track: tracks.first,
                      queue: tracks,
                      index: 0,
                      source: 'playlist',
                    );
                    await notifier.toggleShuffle();
                  },
                ),
                const SizedBox(width: 10),
                _iconButton(
                  c,
                  PhosphorIcons.plus(),
                  () => _addTracks(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < tracks.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 15),
              child: _PlaylistRow(
                track: tracks[i],
                queue: tracks,
                index: i,
                onRemove: () => ref
                    .read(playlistDetailProvider(playlistId).notifier)
                    .removeTrack(tracks[i].id),
              ),
            ),
        ],
      ],
    );
  }

  // ── Шапка ─────────────────────────────────────────────────────────────────

  Widget _bar(BuildContext context, WidgetRef ref, Playlist? p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Row(
        children: [
          AudioSquareButton(
            icon: PhosphorIcons.arrowLeft(),
            onTap: () => context.pop(),
          ),
          const Spacer(),
          if (p != null)
            AudioSquareButton(
              icon: PhosphorIcons.dotsThree(),
              onTap: () => _menu(context, ref, p),
            ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Playlist p) async {
    await showSeeUBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.pencilSimple(), color: c.ink2),
                title: Text('Переименовать',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _rename(context, ref, p);
                },
              ),
              ListTile(
                leading:
                    Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
                title: const Text(
                  'Удалить плейлист',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: SeeUColors.danger),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await showSeeUConfirm(
                    context,
                    title: 'Удалить плейлист?',
                    message:
                        'Сам плейлист исчезнет, но треки останутся — они никуда '
                        'не денутся из Аудиотеки.',
                    confirmLabel: 'Удалить',
                    destructive: true,
                    icon: PhosphorIcons.trash(),
                  );
                  if (!ok) return;
                  await ref.read(myPlaylistsProvider.notifier).delete(p.id);
                  if (context.mounted) context.pop();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, Playlist p) async {
    final ctrl = TextEditingController(text: p.name);
    try {
      await _renameFlow(context, ref, p, ctrl);
    } finally {
      // Контроллер жил вне State — утекал на каждый вызов переименования.
      ctrl.dispose();
    }
  }

  Future<void> _renameFlow(BuildContext context, WidgetRef ref, Playlist p,
      TextEditingController ctrl) async {
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
                'Переименовать',
                style:
                    SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 14),
              SeeUInput(controller: ctrl, autofocus: true),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SeeUButton(
                  label: 'Сохранить',
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
    if (name.isEmpty || name == p.name) return;
    final renamed =
        await ref.read(myPlaylistsProvider.notifier).rename(p.id, name);
    if (!renamed) {
      if (context.mounted) {
        showSeeUSnackBar(context, 'Не удалось переименовать',
            tone: SeeUTone.danger);
      }
      return;
    }
    ref.read(playlistDetailProvider(p.id).notifier).load();
  }

  /// Добавление — чек-лист, а не поход по карточкам треков.
  Future<void> _addTracks(BuildContext context, WidgetRef ref) async {
    final saved = ref.read(savedTracksProvider).valueOrNull ?? const [];
    final trending = ref.read(trendingTracksProvider).valueOrNull ?? const [];
    // Предлагаем то, что человек уже отметил, и то, что набирает — это
    // осмысленнее, чем показывать пустой поиск.
    final pool = <AudioTrack>[
      ...saved,
      ...trending.where((t) => !saved.any((s) => s.id == t.id)),
    ];

    if (pool.isEmpty) {
      showSeeUSnackBar(context, 'Нечего добавить — сохрани что-нибудь сначала');
      return;
    }

    final picked = <String>{};
    await showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = ctx.seeuColors;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
                    child: Text(
                      'Добавить треки',
                      style: SeeUTypography.displayS
                          .copyWith(fontSize: 22, color: c.ink),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in pool)
                          ListTile(
                            leading: TrackCover(track: t, size: 42, radius: 10),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: c.ink),
                            ),
                            subtitle: Text(
                              t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.ink3),
                            ),
                            trailing: Icon(
                              picked.contains(t.id)
                                  ? PhosphorIconsFill.checkCircle
                                  : PhosphorIcons.circle(),
                              color: picked.contains(t.id)
                                  ? SeeUColors.accent
                                  : c.ink4,
                            ),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setSheet(() {
                                if (!picked.remove(t.id)) picked.add(t.id);
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: SeeUButton(
                        label: picked.isEmpty
                            ? 'Выбери треки'
                            : 'Добавить · ${picked.length}',
                        onTap: picked.isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (picked.isEmpty) return;
    for (final id in picked) {
      await ref.read(myPlaylistsProvider.notifier).addTrack(playlistId, id);
    }
    ref.read(playlistDetailProvider(playlistId).notifier).load();
  }

  // ── Пусто ─────────────────────────────────────────────────────────────────

  Widget _empty(BuildContext context) {
    final c = context.seeuColors;
    return Consumer(
      builder: (context, ref, _) => Padding(
        padding: const EdgeInsets.fromLTRB(44, 70, 44, 0),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent.withValues(alpha: 0.1),
              ),
              child: const Icon(PhosphorIconsRegular.plus,
                  size: 38, color: SeeUColors.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Наполним его',
              style:
                  SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавляй треки прямо отсюда или кнопкой «В плейлист» на любой '
              'карточке.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.55, color: c.ink3),
            ),
            const SizedBox(height: 22),
            Tappable.scaled(
              onTap: () => _addTracks(context, ref),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.plus, size: 15, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Добавить треки',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Мелочи ────────────────────────────────────────────────────────────────

  Widget _iconButton(SeeUThemeColors c, IconData icon, VoidCallback onTap) {
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Icon(icon, size: 21, color: c.ink2),
      ),
    );
  }

  static String _word(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'треков';
    if (m10 == 1) return 'трек';
    if (m10 >= 2 && m10 <= 4) return 'трека';
    return 'треков';
  }

  static String _totalTime(List<AudioTrack> tracks) {
    final total = tracks.fold<int>(0, (s, t) => s + t.durationSeconds);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '$h ч ${m > 0 ? '$m мин' : ''}'.trim();
    return '$m мин';
  }
}

// ─── Строка плейлиста ───────────────────────────────────────────────────────

class _PlaylistRow extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int index;
  final VoidCallback onRemove;

  const _PlaylistRow({
    required this.track,
    required this.queue,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final mode = modeOf(track);

    return Dismissible(
      key: ValueKey(track.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8),
        child: Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        onRemove();
        return false;
      },
      child: Tappable.scaled(
        onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
              track: track,
              queue: queue,
              index: index,
              source: 'playlist',
            ),
        child: Row(
          children: [
            TrackCover(
              track: track,
              size: 46,
              radius: 10,
              playing: isCurrent && player.playing,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? mode.color : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (track.artist.isNotEmpty) track.artist,
                      formatDuration(track.durationSeconds),
                    ].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Была иконка-грип перетаскивания (dotsSixVertical), но реордер
            // плейлистов не поддержан — грип вводил в заблуждение. Заменили на
            // настоящую кнопку «убрать из плейлиста» (дублирует свайп).
            Tappable.scaled(
              onTap: onRemove,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(PhosphorIcons.minusCircle(), size: 20, color: c.ink4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
