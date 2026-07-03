import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_provider.dart';

class MyTracksScreen extends ConsumerStatefulWidget {
  const MyTracksScreen({super.key});

  @override
  ConsumerState<MyTracksScreen> createState() => _MyTracksScreenState();
}

class _MyTracksScreenState extends ConsumerState<MyTracksScreen> {
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
    final tracksAsync = ref.watch(myTracksProvider);
    final c = context.seeuColors;

    return Scaffold(
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Мои треки',
            kicker: 'МУЗЫКА',
            leading: const SeeUBackButton(),
            actions: [
              IconButton(
                icon: Icon(PhosphorIcons.plus(), color: SeeUColors.accent),
                tooltip: 'Загрузить',
                onPressed: () async {
                  await context.push('/music/upload');
                  ref.invalidate(myTracksProvider);
                },
              ),
            ],
          ),
          Expanded(
            child: tracksAsync.when(
              loading: () => const SeeUListSkeleton(),
              error: (e, _) => SeeUErrorState(
                onRetry: () => ref.invalidate(myTracksProvider),
              ),
              data: (tracks) {
                if (tracks.isEmpty) {
                  return SeeUEmptyState(
                    icon: PhosphorIconsRegular.musicNotesSimple,
                    title: 'Нет треков',
                    subtitle: 'Загрузите первый трек',
                    action: SeeUStateAction(
                      label: 'Загрузить трек',
                      icon: PhosphorIconsRegular.uploadSimple,
                      onTap: () async {
                        await context.push('/music/upload');
                        ref.invalidate(myTracksProvider);
                      },
                    ),
                  );
                }
                final visible = _apply(tracks);
                return Column(
                  children: [
                    _buildSearchBar(context),
                    Expanded(
                      child: SeeURadarRefresh(
                        onRefresh: () async =>
                            ref.invalidate(myTracksProvider),
                        child: visible.isEmpty
                            ? ListView(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 80, 20, 0),
                                    child: Center(
                                      child: Text(
                                        'По запросу «$_filter» ничего нет',
                                        style: SeeUTypography.body
                                            .copyWith(color: c.ink3),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 8),
                                itemCount: visible.length,
                                itemBuilder: (ctx, i) => _TrackTile(
                                  track: visible[i],
                                  onDeleted: () =>
                                      ref.invalidate(myTracksProvider),
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
    return SeeUGlassSearchBar(
      controller: _searchCtrl,
      hintText: 'Поиск по моим трекам…',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      onChanged: (v) => setState(() => _filter = v.trim()),
      onClear: () {
        _searchCtrl.clear();
        setState(() => _filter = '');
      },
    );
  }
}

class _TrackTile extends ConsumerWidget {
  final AudioTrack track;
  final VoidCallback onDeleted;

  const _TrackTile({required this.track, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final player = ref.watch(miniPlayerProvider);
    final isPlaying = player.track?.id == track.id && player.playing;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Tappable.scaled(
              onTap: () => ref.read(miniPlayerProvider.notifier).play(track),
              child: _CoverWidget(
                  coverUrl: track.coverUrl, isPlaying: isPlaying),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      style: SeeUTypography.subtitle.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (track.artist.isNotEmpty)
                    Text(track.artist,
                        style:
                            SeeUTypography.caption.copyWith(color: c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatusChip(status: track.status),
                      const SizedBox(width: 6),
                      _VisibilityChip(visibility: track.visibility),
                      if (track.durationSeconds > 0) ...[
                        const SizedBox(width: 6),
                        Text(track.durationFormatted,
                            style: SeeUTypography.caption
                                .copyWith(color: c.ink3)),
                      ],
                    ],
                  ),
                  if (track.sizeFormatted.isNotEmpty)
                    Text(
                      [track.category, track.sizeFormatted]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style:
                          SeeUTypography.caption.copyWith(color: c.ink3),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink3),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context, ref);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
                    const SizedBox(width: 8),
                    Text('Удалить',
                        style: TextStyle(color: SeeUColors.danger)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Удалить трек?',
      message: '«${track.title}» будет удалён.',
      confirmLabel: 'Удалить',
      destructive: true,
    );

    if (!confirmed || !context.mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.audioTrackDelete(track.id));
      onDeleted();
      if (context.mounted) {
        showSeeUSnackBar(context, 'Трек удалён', tone: SeeUTone.success);
      }
    } catch (e) {
      if (context.mounted) {
        showSeeUSnackBar(context, 'Не удалось удалить трек',
            tone: SeeUTone.danger);
      }
    }
  }
}

class _CoverWidget extends StatelessWidget {
  final String coverUrl;
  final bool isPlaying;
  const _CoverWidget({required this.coverUrl, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.small),
      child: Stack(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 168,
                    placeholder: (_, __) => _placeholder(),
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: isPlaying ? 0.5 : 0.2),
              ),
              child: Icon(
                isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        color: SeeUColors.accent.withValues(alpha: 0.15),
        child: Icon(PhosphorIcons.musicNote(),
            color: SeeUColors.accent, size: 24),
      );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    Color color;
    String label;
    switch (status) {
      case 'approved':
        color = SeeUColors.success;
        label = 'Готово';
      case 'pending':
        color = SeeUColors.amber;
        label = 'На проверке';
      case 'rejected':
        color = SeeUColors.error;
        label = 'Отклонён';
      default:
        color = c.ink3;
        label = status;
    }
    return _Chip(label: label, color: color);
  }
}

class _VisibilityChip extends StatelessWidget {
  final String visibility;
  const _VisibilityChip({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    switch (visibility) {
      case 'public':
        return _Chip(label: 'Публичный', color: SeeUColors.accent);
      case 'private':
        return _Chip(label: 'Приватный', color: SeeUColors.plum);
      case 'unlisted':
        return _Chip(label: 'По ссылке', color: SeeUColors.amber);
      default:
        return _Chip(label: visibility, color: c.ink3);
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
