import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_provider.dart';

class SavedTracksScreen extends ConsumerStatefulWidget {
  const SavedTracksScreen({super.key});

  @override
  ConsumerState<SavedTracksScreen> createState() => _SavedTracksScreenState();
}

class _SavedTracksScreenState extends ConsumerState<SavedTracksScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AudioTrack> _apply(List<AudioTrack> tracks) {
    if (_filter.isEmpty) return tracks;
    final q = _filter.toLowerCase();
    return tracks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.displayArtist.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(savedTracksProvider);

    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Сохранённые треки',
            kicker: 'МУЗЫКА',
            leading: const SeeUBackButton(),
          ),
          Expanded(
            child: tracksAsync.when(
        loading: () => const SeeUListSkeleton(),
        error: (_, __) => SeeUErrorState(
          onRetry: () => ref.invalidate(savedTracksProvider),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const SeeUEmptyState(
              icon: PhosphorIconsRegular.bookmarkSimple,
              title: 'Нет сохранённых треков',
              subtitle: 'Нажмите на трек чтобы сохранить',
            );
          }
          final visible = _apply(tracks);
          return Column(
            children: [
              _buildSearchBar(context),
              Expanded(
                child: SeeURadarRefresh(
                  onRefresh: () async => ref.invalidate(savedTracksProvider),
                  child: visible.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 80, 20, 0),
                              child: Center(
                                child: Text(
                                  'По запросу «$_filter» ничего нет',
                                  style: SeeUTypography.caption
                                      .copyWith(color: c.ink3),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => _SavedTrackTile(
                            track: visible[i],
                            queue: visible,
                            queueIndex: i,
                            onUnsaved: () =>
                                ref.invalidate(savedTracksProvider),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SeeUGlassSearchBar(
        controller: _searchCtrl,
        hintText: 'Поиск по сохранённым…',
        onChanged: (v) => setState(() => _filter = v.trim()),
        onClear: _filter.isNotEmpty
            ? () {
                _searchCtrl.clear();
                setState(() => _filter = '');
              }
            : null,
      ),
    );
  }
}

class _SavedTrackTile extends ConsumerWidget {
  final AudioTrack track;
  final List<AudioTrack> queue;
  final int queueIndex;
  final VoidCallback onUnsaved;

  const _SavedTrackTile({
    required this.track,
    required this.queue,
    required this.queueIndex,
    required this.onUnsaved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;

    return InkWell(
      onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: queue,
            index: queueIndex,
            source: 'saved',
          ),
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
                        errorWidget: (_, __, ___) => _placeholder(c),
                      )
                    : _placeholder(c),
              ),
            ),
            const SizedBox(width: 12),
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
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.ink2),
                  ),
                ],
              ),
            ),
            Text(
              track.durationFormatted,
              style: TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 11, color: c.ink3),
            ),
            const SizedBox(width: 4),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 28,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              icon:
                  Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink2, size: 18),
              onPressed: () => _showActions(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(SeeUThemeColors c) => Container(
        color: c.surface2,
        child:
            Icon(PhosphorIcons.musicNotesSimple(), color: c.ink3, size: 20),
      );

  void _showActions(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.musicNote(), color: c.ink),
              title: const Text('Открыть трек'),
              onTap: () {
                Navigator.pop(sheetCtx);
                context.push('/music/track/${track.id}');
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.bookmarkSimple(),
                  color: SeeUColors.error),
              title: Text('Убрать из сохранённых',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.error)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await ref
                      .read(apiClientProvider)
                      .delete(ApiEndpoints.audioTrackSave(track.id));
                  onUnsaved();
                } catch (_) {
                  if (context.mounted) {
                    showSeeUSnackBar(
                        context, 'Не удалось убрать из сохранённых',
                        tone: SeeUTone.danger);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
