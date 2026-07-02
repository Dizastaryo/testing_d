import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/models/playlist.dart';
import '../../core/providers/audio_discovery_provider.dart';
import '../../core/providers/playlist_provider.dart';

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
  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);
    final discovery = ref.watch(audioDiscoveryProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SeeURadarRefresh(
        onRefresh: () async {
          ref.invalidate(audioDiscoveryProvider);
          await ref.read(audioDiscoveryProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(theme, c)),
            SliverToBoxAdapter(child: _NowPlayingFriendsRow()),
            // Recently played — only shown if backend returns data.
            // Must be a sliver at every state (loading, error, empty, data).
            discovery.when(
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.recentlyPlayed.isNotEmpty
                  ? _buildHorizontalSection(
                      title: 'Продолжить',
                      kicker: 'НЕДАВНЕЕ',
                      tracks: d.recentlyPlayed,
                      source: 'recently_played',
                      c: c,
                      theme: theme,
                    )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            SliverToBoxAdapter(child: _DailyMixCard()),
            // Trending from discovery — ranked list
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.trendingTracks.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: _TrendingSection(tracks: d.trendingTracks),
                    ),
            ),
            // Categories grid
            SliverToBoxAdapter(child: _CategoriesGrid()),
            // Original sounds — sounds extracted from videos
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.originalSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: _OriginalSoundsSection(tracks: d.originalSounds),
                    ),
            ),
            // Video sounds — cards with Использовать CTA
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.videoSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: _VideoSoundsSection(tracks: d.videoSounds),
                    ),
            ),
            // Meme sounds
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.memeSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: _DiscoveryTrackCarousel(
                        title: 'Мемы',
                        kicker: 'ЗВУКИ',
                        tracks: d.memeSounds,
                        source: 'memes',
                        onSeeAll: () => context.push('/music/category/memes'),
                      ),
                    ),
            ),
            // New releases
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.newTracks.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: _DiscoveryTrackCarousel(
                        title: 'Новинки',
                        kicker: 'СВЕЖЕЕ',
                        tracks: d.newTracks,
                        source: 'new_tracks',
                      ),
                    ),
            ),
            SliverToBoxAdapter(child: _buildPlaylistsStrip(c)),
            SliverToBoxAdapter(child: _buildMyUploadsSection(c)),
            // Error/loading state for full discovery
            if (discovery.isLoading)
              const SliverToBoxAdapter(
                child: SizedBox(height: 200, child: SeeUListSkeleton(count: 3)),
              ),
            if (discovery.hasError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SeeUErrorState(
                    title: 'Не удалось загрузить разделы музыки',
                    onRetry: () => ref.invalidate(audioDiscoveryProvider),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalSection({
    required String title,
    required String kicker,
    required List<AudioTrack> tracks,
    required String source,
    required SeeUThemeColors c,
    required ThemeData theme,
    VoidCallback? onSeeAll,
  }) {
    return SliverToBoxAdapter(
      child: _DiscoveryTrackCarousel(
        title: title,
        kicker: kicker,
        tracks: tracks,
        source: source,
        onSeeAll: onSeeAll,
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, SeeUThemeColors c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '◆ AUDIO LIBRARY',
            style: SeeUTypography.kicker
                .copyWith(color: SeeUColors.accent, letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Text(
            'Музыка',
            style: SeeUTypography.displayL.copyWith(
              fontSize: 36,
              letterSpacing: -1,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Музыка, мемы, подкасты и звуки',
            style: SeeUTypography.caption.copyWith(color: c.ink3),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => context.push('/music/search'),
            child: const AbsorbPointer(
              child: SeeUGlassSearchBar(
                hintText: 'Поиск по трекам, артистам…',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _QuickButton(
                  icon: PhosphorIcons.uploadSimple(),
                  label: 'Загрузить',
                  onTap: () async {
                    await context.push('/music/upload');
                    ref.invalidate(audioDiscoveryProvider);
                    ref.invalidate(_myTracksProvider);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: PhosphorIcons.musicNote(),
                  label: 'Мои треки',
                  onTap: () => context.push('/music/mine'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: PhosphorIcons.bookmarkSimple(),
                  label: 'Сохранённые',
                  onTap: () => context.push('/music/saved'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: PhosphorIcons.queue(),
                  label: 'Плейлисты',
                  onTap: _openPlaylistsSheet,
                ),
              ),
            ],
          ),
        ],
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
              SeeUSectionHeader(
                kicker: 'ЗАГРУЗКИ',
                title: 'Мои треки',
                padding: EdgeInsets.zero,
                action: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: SeeUColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => context.push('/music/mine'),
                  child:
                      const Text('Все →', style: TextStyle(fontSize: 13)),
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
      'pending' => ('На модерации', SeeUColors.warning),
      'rejected' => ('Отклонён', SeeUColors.error),
      _ => ('Опубликован', SeeUColors.success),
    };
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == t.id;
    final isPlaying = isCurrent && player.playing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          if (isCurrent) {
            ref.read(miniPlayerProvider.notifier).toggle();
          } else {
            ref.read(miniPlayerProvider.notifier).playWithQueue(
              track: t, queue: [t], index: 0, source: 'my_tracks');
          }
        },
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
                            style: const TextStyle(
                                fontSize: 11,
                                color: SeeUColors.error,
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
                    ? PhosphorIconsFill.pauseCircle
                    : PhosphorIconsFill.playCircle,
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
    return Consumer(
      builder: (_, ref, __) {
        final async = ref.watch(myPlaylistsProvider);
        final list = async.value ?? const <Playlist>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SeeUSectionHeader(
                kicker: 'КОЛЛЕКЦИИ',
                title: 'Мои плейлисты',
                padding: EdgeInsets.zero,
                action: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: SeeUColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _createPlaylistDialog,
                  icon: Icon(PhosphorIcons.plus(), size: 16),
                  label: const Text('Новый'),
                ),
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
    final String? name;
    try {
      name = await showDialog<String>(
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
    } finally {
      ctrl.dispose();
    }
    if (name == null || name.isEmpty) return;
    final p = await ref.read(myPlaylistsProvider.notifier).create(name);
    if (!mounted) return;
    if (p != null) {
      showSeeUSnackBar(context, 'Плейлист «${p.name}» создан',
          tone: SeeUTone.success);
    } else {
      showSeeUSnackBar(context, 'Не удалось создать плейлист',
          tone: SeeUTone.danger);
    }
  }

  void _openPlaylistsSheet() {
    final c = context.seeuColors;
    showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Consumer(
        builder: (_, ref, __) {
          final async = ref.watch(myPlaylistsProvider);
          final list = async.value ?? const <Playlist>[];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Icon(PhosphorIcons.queue(), color: SeeUColors.accent),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Мои плейлисты',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: SeeUColors.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await _createPlaylistDialog();
                          },
                          icon: Icon(PhosphorIcons.plus(), size: 16),
                          label: const Text('Новый'),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  Flexible(
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('У вас ещё нет плейлистов',
                                style: TextStyle(color: c.ink2)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
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
                                        : Container(
                                            color: c.surface2,
                                            child: Icon(
                                                PhosphorIcons.musicNotesSimple(),
                                                color: c.ink3,
                                                size: 18),
                                          ),
                                  ),
                                ),
                                title: Text(p.name),
                                subtitle: Text('${p.tracksCount} треков',
                                    style:
                                        TextStyle(color: c.ink3, fontSize: 11)),
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  context.push('/playlist/${p.id}');
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

}

// ── Phase 5: Discovery widgets ────────────────────────────────────────────────

/// Horizontal carousel for a list of tracks with a section header.
class _DiscoveryTrackCarousel extends ConsumerWidget {
  final String title;
  final String kicker;
  final List<AudioTrack> tracks;
  final String source;
  final VoidCallback? onSeeAll;

  const _DiscoveryTrackCarousel({
    required this.title,
    required this.kicker,
    required this.tracks,
    required this.source,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeeUSectionHeader(
            kicker: kicker,
            title: title,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            action: onSeeAll != null
                ? TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: SeeUColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onSeeAll,
                    child: const Text('Все →', style: TextStyle(fontSize: 13)),
                  )
                : null,
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _TrackCard(
                track: tracks[i],
                queue: tracks,
                index: i,
                source: source,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int index;
  final String source;

  const _TrackCard({
    required this.track,
    required this.queue,
    required this.index,
    required this.source,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return GestureDetector(
      onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: queue,
            index: index,
            source: source,
          ),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent
              ? Border.all(color: SeeUColors.accent, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: SeeUColors.accent.withValues(alpha: 0.15),
                        child: Icon(PhosphorIcons.musicNote(),
                            size: 18, color: SeeUColors.accent),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(PhosphorIcons.heart(), size: 10, color: c.ink3),
                      const SizedBox(width: 3),
                      Text('${track.likesCount}',
                          style: TextStyle(
                              fontSize: 10,
                              color: c.ink3,
                              fontFamily: 'JetBrains Mono')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of category cards for the browse section.
class _CategoriesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cats = kAudioCategories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'КАТАЛОГ',
            title: 'Разделы',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.15,
            ),
            itemCount: cats.length,
            itemBuilder: (_, i) => _CategoryCard(cat: cats[i]),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final AudioCategoryModel cat;
  const _CategoryCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/music/category/${cat.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cat.color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(cat.iconData, size: 22, color: cat.color),
            const Spacer(),
            Text(
              cat.titleRu,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cat.color,
              ),
            ),
          ],
        ),
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
          ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: _tracks.first,
            queue: _tracks,
            index: 0,
            source: 'daily_mix',
          );
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

// ── Phase 6: Premium Discovery UX ────────────────────────────────────────────

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: SeeUColors.accent),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendingSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const _TrendingSection({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = tracks.take(10).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ЧАРТ',
            title: 'Тренды',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          ),
          ...top.asMap().entries.map(
                (e) => _TrendingTile(
                  track: e.value,
                  rank: e.key + 1,
                  queue: tracks,
                ),
              ),
        ],
      ),
    );
  }
}

class _TrendingTile extends ConsumerWidget {
  final AudioTrack track;
  final int rank;
  final List<AudioTrack> queue;

  const _TrendingTile({
    required this.track,
    required this.rank,
    required this.queue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;

    return InkWell(
      onTap: () {
        final idx = queue.indexWhere((t) => t.id == track.id);
        ref.read(miniPlayerProvider.notifier).playWithQueue(
              track: track,
              queue: queue,
              index: idx >= 0 ? idx : 0,
              source: 'trending',
            );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: rank <= 3 ? 16 : 13,
                  fontWeight:
                      rank <= 3 ? FontWeight.w800 : FontWeight.w500,
                  color: rank == 1
                      ? SeeUColors.medalGold
                      : rank == 2
                          ? SeeUColors.medalSilver
                          : rank == 3
                              ? SeeUColors.medalBronze
                              : c.ink3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIcons.musicNote(),
                            color: c.ink3, size: 18),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.displayArtist,
                          style: TextStyle(fontSize: 12, color: c.ink2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track.playsCount > 0) ...[
                        Text('  ·  ',
                            style: TextStyle(color: c.ink3, fontSize: 12)),
                        Icon(PhosphorIcons.play(), size: 10, color: c.ink3),
                        const SizedBox(width: 2),
                        Text(
                          _fmt(track.playsCount),
                          style: TextStyle(
                            fontSize: 11,
                            color: c.ink3,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

class _VideoSoundsSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const _VideoSoundsSection({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ДЛЯ РОЛИКОВ',
            title: 'Звуки для видео',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _VideoSoundCard(
                track: tracks[i],
                queue: tracks,
                index: i,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSoundCard extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int index;

  const _VideoSoundCard({
    required this.track,
    required this.queue,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent
            ? Border.all(color: SeeUColors.accent, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () =>
                    ref.read(miniPlayerProvider.notifier).playWithQueue(
                          track: track,
                          queue: queue,
                          index: index,
                          source: 'video_sounds',
                        ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: track.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: c.surface2),
                          )
                        : Container(
                            color: SeeUColors.accent.withValues(alpha: 0.15),
                            child: Icon(PhosphorIcons.videoCamera(),
                                size: 18, color: SeeUColors.accent),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? SeeUColors.accent : c.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Original Sounds Section ───────────────────────────────────────────────────

class _OriginalSoundsSection extends ConsumerWidget {
  final List<AudioTrack> tracks;
  const _OriginalSoundsSection({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SeeUSectionHeader(
            kicker: 'ИЗ ВИДЕО',
            title: 'Оригинальные звуки',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _OriginalSoundTile(
              track: tracks[i],
              ref: ref,
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalSoundTile extends StatelessWidget {
  final AudioTrack track;
  final WidgetRef ref;
  const _OriginalSoundTile({required this.track, required this.ref});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;

    return GestureDetector(
      onTap: () => context.push('/music/track/${track.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent
                ? SeeUColors.accent.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent.withValues(alpha: 0.15),
              ),
              child: Icon(
                PhosphorIconsRegular.videoCamera,
                size: 16,
                color: SeeUColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (track.usesCount > 0)
              Text(
                '${track.usesCount} видео',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: c.ink3,
                ),
              ),
          ],
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
          const SeeUSectionHeader(
            kicker: 'ДРУЗЬЯ',
            title: 'Слушают сейчас',
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                                  image: CachedNetworkImageProvider(n.coverUrl,
                                      maxWidth: 96, maxHeight: 96),
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

