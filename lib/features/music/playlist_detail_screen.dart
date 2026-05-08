import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
  final _player = AudioPlayer();
  AudioTrack? _current;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleTrack(AudioTrack track) async {
    try {
      if (_current?.id == track.id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        setState(() {});
        return;
      }
      setState(() => _current = track);
      await _player.setUrl(track.audioUrl);
      await _player.play();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось проиграть: $e')),
      );
    }
  }

  Future<void> _renamePlaylist(String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final name = await showDialog<String>(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переименовать')),
      );
    }
  }

  Future<void> _deletePlaylist(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Удалить плейлист?'),
        content: Text('«$name» будет удалён, треки останутся в каталоге.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .delete(widget.playlistId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    final async = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: async.maybeWhen(
          data: (d) => Text(d.playlist.name),
          orElse: () => const Text(''),
        ),
        actions: [
          async.maybeWhen(
            data: (d) => PopupMenuButton<String>(
              icon: Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink),
              onSelected: (v) {
                if (v == 'rename') {
                  _renamePlaylist(d.playlist.name);
                } else if (v == 'delete') {
                  _deletePlaylist(d.playlist.name);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить',
                        style: TextStyle(color: Colors.red))),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Ошибка: $e', style: TextStyle(color: c.ink2)),
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
                            _trackTile(d.tracks[i], c),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                  ),
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

  Widget _trackTile(AudioTrack track, SeeUThemeColors c) {
    final isCurrent = _current?.id == track.id;
    final isPlaying = isCurrent && _player.playing;
    return InkWell(
      onTap: () => _toggleTrack(track),
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
                    '${track.artist} · ${track.genre}',
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
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Удалено из плейлиста' : 'Ошибка'),
                  ),
                );
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
