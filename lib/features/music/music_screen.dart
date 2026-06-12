import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/models/playlist.dart';
import '../../core/providers/playlist_provider.dart';
import '../../core/providers/post_compose_provider.dart';
import 'track_upload_sheet.dart';

final _tracksProvider =
    FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.audioTracks);
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final list = (data is List ? data : (data as Map)['items'] as List? ?? []);
  return list
      .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Tracks uploaded by the current user (any status — pending/approved/rejected).
final _myTracksProvider =
    FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final r = await api.get(ApiEndpoints.myAudioTracks);
    final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
    final list = data is List ? data : <dynamic>[];
    return list
        .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <AudioTrack>[];
  }
});

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  // Music screen больше не владеет собственным плеером — переходим на
  // глобальный AudioPlayerService через провайдер. Это даёт persistent
  // mini-player'у переживать навигацию между экранами и hot-reload'ом
  // music_screen'а не убивает воспроизведение.
  AudioPlayer get _player =>
      ref.read(audioPlayerServiceProvider).raw;
  AudioTrack? get _current =>
      ref.watch(miniPlayerProvider).track;

  String _query = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  // Optimistic like state managed by SeeULikeButton internally.
  // No local maps needed — SeeULikeButton handles rollback on error.

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleTrack(AudioTrack track) async {
    try {
      await ref.read(miniPlayerProvider.notifier).play(track);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось проиграть: $e')),
      );
    }
  }

  Future<void> _likeTrack(AudioTrack track, bool newLikedState) async {
    final api = ref.read(apiClientProvider);
    if (newLikedState) {
      await api.post('${ApiEndpoints.audioTracks}/${track.id}/like');
    } else {
      await api.delete('${ApiEndpoints.audioTracks}/${track.id}/like');
    }
  }

  List<AudioTrack> _applySearch(List<AudioTrack> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.genre.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    final async = ref.watch(_tracksProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: SeeURadarRefresh(
              onRefresh: () async {
                ref.invalidate(_tracksProvider);
                // Wait for next provider load to settle so the spinner
                // doesn't yank closed before data lands.
                await ref.read(_tracksProvider.future);
              },
              child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(theme, c)),
                if (_searchOpen) SliverToBoxAdapter(child: _buildSearch()),
                // MUSIC-1: «🎵 Слушают сейчас» — horizontal row друзей.
                if (!_searchOpen)
                  SliverToBoxAdapter(child: _NowPlayingFriendsRow()),
                // MUSIC-4: «🌅 Твой день» hero-card — daily mix.
                if (!_searchOpen)
                  SliverToBoxAdapter(child: _DailyMixCard()),
                if (!_searchOpen)
                  SliverToBoxAdapter(child: _buildPlaylistsStrip(c)),
                if (!_searchOpen)
                  SliverToBoxAdapter(child: _buildMyUploadsSection(c)),
                async.when(
                  loading: () => const SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: SeeUListSkeleton(count: 6),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Не удалось загрузить треки: $e',
                          style: TextStyle(color: c.ink2)),
                    ),
                  ),
                  data: (tracks) {
                    final list = _applySearch(tracks);
                    if (list.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'Треков пока нет'
                                  : 'По запросу «$_query» ничего',
                              style: TextStyle(color: c.ink3),
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => _trackTile(list[i], c),
                      ),
                    );
                  },
                ),
              ],
            ),
            ),
          ),
          // Дополнительный inline-плеер на экране music убран:
          // персистентный SeeUMiniPlayer теперь живёт над bottom-nav и
          // сопровождает юзера через все экраны.
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, SeeUThemeColors c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '◆ AUDIO LIBRARY',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Музыка',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  final ok = await showTrackUploadSheet(context, ref);
                  if (ok) {
                    ref.invalidate(_tracksProvider);
                    ref.invalidate(_myTracksProvider);
                  }
                },
                icon: Icon(PhosphorIcons.uploadSimple(),
                    color: theme.colorScheme.onSurface),
                tooltip: 'Загрузить свой трек',
              ),
              IconButton(
                onPressed: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    _query = '';
                  }
                }),
                icon: Icon(
                  _searchOpen ? PhosphorIconsRegular.x : PhosphorIconsRegular.magnifyingGlass,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Поиск по трекам, артистам, жанрам…',
          prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
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
                          fontWeight: FontWeight.w600, color: isCurrent ? SeeUColors.accent : c.ink)),
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
            SeeULikeButton(
              isLiked: track.isLiked,
              count: track.likesCount,
              iconSize: 20,
              onToggle: (newState) => _likeTrack(track, newState),
            ),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 32,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink2),
              onPressed: () => _showTrackActions(track),
              tooltip: 'Действия',
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // My uploaded tracks (with moderation status)
  // ---------------------------------------------------------------------------

  Widget _buildMyUploadsSection(SeeUThemeColors c) {
    return Consumer(
      builder: (_, ref, __) {
        final async = ref.watch(_myTracksProvider);
        final list = async.value ?? const <AudioTrack>[];
        if (list.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Мои треки',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...list.map((t) => _myTrackTile(t, c)),
            ],
          ),
        );
      },
    );
  }

  Widget _myTrackTile(AudioTrack t, SeeUThemeColors c) {
    final (label, color) = switch (t.status) {
      'pending' => ('На модерации', const Color(0xFFEF8C00)),
      'rejected' => ('Отклонён', const Color(0xFFE53935)),
      _ => ('Опубликован', const Color(0xFF43A047)),
    };
    final isCurrent = _current?.id == t.id;
    final isPlaying = isCurrent && _player.playing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _toggleTrack(t),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                          child: Icon(PhosphorIcons.musicNotesSimple(),
                              color: c.ink3, size: 18),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                    if (t.status == 'rejected' &&
                        t.rejectionReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.rejectionReason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade400,
                                fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              Icon(
                isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: isCurrent ? SeeUColors.accent : c.ink3,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Playlists strip + actions
  // ---------------------------------------------------------------------------

  Widget _buildPlaylistsStrip(SeeUThemeColors c) {
    final theme = Theme.of(context);
    return Consumer(
      builder: (_, ref, __) {
        final async = ref.watch(myPlaylistsProvider);
        final list = async.value ?? const <Playlist>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Мои плейлисты',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: SeeUColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _createPlaylistDialog,
                    icon: Icon(PhosphorIcons.plus(), size: 16),
                    label: const Text('Новый'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 134,
                child: list.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Создайте первый, чтобы сохранять любимые треки',
                            style: TextStyle(color: c.ink3, fontSize: 12),
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _playlistCard(list[i], c),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _playlistCard(Playlist p, SeeUThemeColors c) {
    return GestureDetector(
      onTap: () => context.push('/playlist/${p.id}'),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 90,
                child: p.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: p.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIcons.musicNotesSimple(),
                            color: c.ink3, size: 32),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${p.tracksCount} треков',
                style: TextStyle(color: c.ink3, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _createPlaylistDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Название'),
          onSubmitted: (v) =>
              Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final p = await ref.read(myPlaylistsProvider.notifier).create(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(p != null
            ? 'Плейлист «${p.name}» создан'
            : 'Не удалось создать плейлист'),
      ),
    );
  }

  Future<void> _showTrackActions(AudioTrack track) async {
    final c = context.seeuColors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.queue(), color: c.ink),
              title: const Text('Добавить в плейлист'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showAddToPlaylistSheet(track);
              },
            ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.filmSlate(), color: SeeUColors.accent),
              title: const Text('Использовать в рилсе'),
              subtitle: const Text(
                  'Откроет камеру в режиме рилса с этим треком'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _useTrackInReel(track);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _useTrackInReel(AudioTrack track) {
    // Stash the track so MediaPrepareScreen picks it up on initState. Camera
    // defaults to reel-mode tab, user records video, hits «Далее» and lands
    // in MediaPrepare with publish mode = Reel and audio preselected.
    ref.read(pendingPostTrackProvider.notifier).state = track;
    context.push('/story/create');
  }

  Future<void> _showAddToPlaylistSheet(AudioTrack track) async {
    final c = context.seeuColors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer(
        builder: (consumerCtx, ref, _) {
          final async = ref.watch(myPlaylistsProvider);
          final list = async.value ?? const <Playlist>[];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(consumerCtx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Icon(PhosphorIcons.queue(),
                            color: SeeUColors.accent),
                        const SizedBox(width: 8),
                        Text('Добавить «${track.title}»',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  ListTile(
                    leading: Icon(PhosphorIcons.plus(),
                        color: SeeUColors.accent),
                    title: const Text('Создать новый плейлист'),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      await _createAndAdd(track);
                    },
                  ),
                  if (list.isNotEmpty) Divider(height: 1, color: c.line),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'У вас ещё нет плейлистов',
                                style: TextStyle(color: c.ink2),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final p = list[i];
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: p.coverUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: p.coverUrl,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Container(color: c.surface2),
                                          )
                                        : Container(color: c.surface2),
                                  ),
                                ),
                                title: Text(p.name),
                                subtitle: Text('${p.tracksCount} треков',
                                    style: TextStyle(
                                        color: c.ink3, fontSize: 11)),
                                onTap: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  Navigator.pop(sheetCtx);
                                  final ok = await ref
                                      .read(myPlaylistsProvider.notifier)
                                      .addTrack(p.id, track.id);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Добавлено в «${p.name}»'
                                          : 'Не удалось добавить'),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createAndAdd(AudioTrack track) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Название'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Создать и добавить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final notifier = ref.read(myPlaylistsProvider.notifier);
    final p = await notifier.create(name);
    if (p == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать плейлист')),
      );
      return;
    }
    final ok = await notifier.addTrack(p.id, track.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Создан «${p.name}» и трек добавлен'
            : 'Плейлист создан, но трек не добавился'),
      ),
    );
  }
}

/// MUSIC-4: hero-карточка «🌅 Твой день» — daily mix. Тап = play первого
/// трека (последующие очередью идут через _service). Если backend ничего
/// не отдал — карточка скрыта.
class _DailyMixCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DailyMixCard> createState() => _DailyMixCardState();
}

class _DailyMixCardState extends ConsumerState<_DailyMixCard> {
  List<AudioTrack> _tracks = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.dailyMixTracks,
          queryParameters: {'limit': '20'});
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
              .toList()
          : <AudioTrack>[];
      if (mounted) {
        setState(() {
          _tracks = list;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _tracks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: GestureDetector(
        onTap: () {
          ref.read(miniPlayerProvider.notifier).play(_tracks.first);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: SeeUGradients.heroOrange,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(PhosphorIconsRegular.sun,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Твой день',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_tracks.length} треков по твоим интересам',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(PhosphorIconsRegular.play,
                  color: Colors.white, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// MUSIC-1: horizontal row друзей которые сейчас слушают музыку.
/// Появляется только когда есть активные слушатели среди подписок.
class _NowPlayingFriendsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(nowPlayingFriendsProvider);
    if (friends.isEmpty) return const SizedBox.shrink();
    final c = context.seeuColors;
    final list = friends.values.toList()
      ..sort((a, b) => b.since.compareTo(a.since)); // newest first
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.musicNote,
                    color: SeeUColors.accent, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Слушают сейчас',
                  style: SeeUTypography.subtitle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final n = list[i];
                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: SeeUGradients.heroOrange,
                          borderRadius: BorderRadius.circular(8),
                          image: n.coverUrl.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(n.coverUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: n.coverUrl.isEmpty
                            ? const Icon(PhosphorIconsRegular.musicNote,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              n.title.isNotEmpty ? n.title : 'Трек',
                              style: SeeUTypography.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              n.artist,
                              style: SeeUTypography.micro
                                  .copyWith(color: c.ink3, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
