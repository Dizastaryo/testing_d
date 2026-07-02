import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/playlist_provider.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  Future<void> _toggleTrack(AudioTrack track, List<AudioTrack> queue) async {
    final notifier = ref.read(miniPlayerProvider.notifier);
    final current = ref.read(miniPlayerProvider).track;
    if (current?.id == track.id) {
      await notifier.toggle();
    } else {
      final idx = queue.indexWhere((t) => t.id == track.id);
      await notifier.playWithQueue(
        track: track,
        queue: queue,
        index: idx >= 0 ? idx : 0,
        source: 'playlist',
      );
    }
  }

  Future<void> _renamePlaylist(String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final String? name;
    try {
      name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Переименовать плейлист'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    } finally {
      ctrl.dispose();
    }
    if (name == null || name.isEmpty || name == currentName) return;
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .rename(widget.playlistId, name);
    if (!mounted) return;
    if (ok) {
      // Reload detail to reflect new name in app bar.
      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .load();
    } else {
      showSeeUSnackBar(context, 'Не удалось переименовать',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _deletePlaylist(String name) async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Удалить плейлист?',
      message: '«$name» будет удалён, треки останутся в каталоге.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIcons.trash(),
    );
    if (!confirmed) return;
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .delete(widget.playlistId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      showSeeUSnackBar(context, 'Не удалось удалить', tone: SeeUTone.danger);
    }
  }

  void _showPlaylistMenu(String playlistName) {
    final c = context.seeuColors;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.pencilSimple(), color: c.ink),
              title: Text('Переименовать',
                  style: SeeUTypography.body.copyWith(color: c.ink)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _renamePlaylist(playlistName);
              },
            ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
              title: Text('Удалить',
                  style:
                      SeeUTypography.body.copyWith(color: SeeUColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _deletePlaylist(playlistName);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    final async = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          SeeUGlassBar(
            kicker: 'ПЛЕЙЛИСТ',
            title: async.maybeWhen(
              data: (d) => Text(d.playlist.name,
                  style: SeeUTypography.displayS.copyWith(color: c.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              orElse: () => const SizedBox.shrink(),
            ),
            leading: Tappable.scaled(
              onTap: () => Navigator.of(context).pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), color: c.ink, size: 22),
              ),
            ),
            actions: [
              async.maybeWhen(
                data: (d) => IconButton(
                  icon: Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink),
                  onPressed: () => _showPlaylistMenu(d.playlist.name),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          Expanded(
            child: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: SeeUColors.accent)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Ошибка: $e',
                style: SeeUTypography.body.copyWith(color: c.ink2)),
          ),
        ),
        data: (d) => Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header(d.playlist.coverUrl,
                      d.playlist.name, d.tracks.length, c)),
                  if (d.tracks.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'Плейлист пуст. Добавьте треки из каталога.',
                            style: TextStyle(color: c.ink3),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                      sliver: SliverList.builder(
                        itemCount: d.tracks.length,
                        itemBuilder: (_, i) =>
                            _trackTile(d.tracks[i], d.tracks, c),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
          ),
        ],
      ),
    );
  }

  Widget _header(String coverUrl, String name, int count, SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 100,
              height: 100,
              child: coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: c.surface2),
                      errorWidget: (_, __, ___) =>
                          Container(color: c.surface2),
                    )
                  : Container(
                      color: c.surface2,
                      child: Icon(PhosphorIcons.musicNotesSimple(),
                          color: c.ink3, size: 36),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: SeeUTypography.displayS,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text('$count треков', style: TextStyle(color: c.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackTile(AudioTrack track, List<AudioTrack> queue, SeeUThemeColors c) {
    final playerState = ref.watch(miniPlayerProvider);
    final isCurrent = playerState.track?.id == track.id;
    final isPlaying = isCurrent && playerState.playing;
    return InkWell(
      onTap: () => _toggleTrack(track, queue),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(color: c.surface2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? SeeUColors.accent : c.ink)),
                  const SizedBox(height: 2),
                  Text(
                    track.genre.isNotEmpty
                        ? '${track.artist} · ${track.genre}'
                        : track.artist,
                    style: TextStyle(fontSize: 12, color: c.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(track.durationFormatted,
                style: TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 11, color: c.ink3)),
            const SizedBox(width: 4),
            Icon(
              isPlaying ? PhosphorIconsFill.pauseCircle : PhosphorIconsFill.playCircle,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 32,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(PhosphorIcons.x(), color: c.ink2, size: 18),
              tooltip: 'Удалить из плейлиста',
              onPressed: () async {
                final ok = await ref
                    .read(playlistDetailProvider(widget.playlistId).notifier)
                    .removeTrack(track.id);
                if (!mounted) return;
                showSeeUSnackBar(
                    context, ok ? 'Удалено из плейлиста' : 'Ошибка',
                    tone: ok ? SeeUTone.success : SeeUTone.danger);
                if (ok) {
                  // Refresh main list (cover + tracks_count may change).
                  ref.read(myPlaylistsProvider.notifier).load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
