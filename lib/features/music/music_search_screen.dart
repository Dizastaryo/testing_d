import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_discovery_provider.dart';

class MusicSearchScreen extends ConsumerStatefulWidget {
  final String initialCategory;
  const MusicSearchScreen({super.key, this.initialCategory = ''});

  @override
  ConsumerState<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends ConsumerState<MusicSearchScreen> {
  final _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  late String _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  AudioSearchParams get _params =>
      AudioSearchParams(query: _query, category: _category);

  bool get _hasInput => _query.length >= 2 || _category.isNotEmpty;

  /// Prepositional ("в …") category phrases so the hint reads naturally,
  /// e.g. "Поиск в Аудиокнигах". Falls back to the nominative category name,
  /// then to a generic phrase for unknown ids.
  static const _categoryPrepositional = <String, String>{
    'music': 'Музыке',
    'memes': 'Мемах',
    'audiobooks': 'Аудиокнигах',
    'podcasts': 'Подкастах',
    'education': 'Образовании',
    'meditation': 'Медитации',
    'news': 'Новостях',
    'instrumental': 'Инструментале',
  };

  /// Context-aware search hint: category-scoped vs. global.
  String get _searchHint {
    if (_category.isEmpty) return 'Трек, артист, жанр…';
    final prep = _categoryPrepositional[_category];
    if (prep != null) return 'Поиск в $prep';
    final name = findCategory(_category)?.titleRu;
    return name != null ? 'Поиск в $name' : 'Поиск в категории';
  }

  void _playTrack(AudioTrack track, List<AudioTrack> queue) async {
    final idx = queue.indexWhere((t) => t.id == track.id);
    try {
      await ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: queue,
            index: idx >= 0 ? idx : 0,
            source: 'search',
          );
    } catch (_) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось воспроизвести трек',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(c, theme),
          _buildCategoryFilter(c),
          Expanded(child: _buildResults(c)),
        ],
      ),
    );
  }

  Widget _buildTopBar(SeeUThemeColors c, ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 8, 16, 8),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          const SeeUBackButton(),
          const SizedBox(width: 8),
          Expanded(
            child: SeeUGlassSearchBar(
              controller: _ctrl,
              focusNode: _focus,
              hintText: _searchHint,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _query = v.trim());
                });
              },
              onClear: _query.isNotEmpty
                  ? () {
                      _debounce?.cancel();
                      _ctrl.clear();
                      setState(() => _query = '');
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(SeeUThemeColors c) {
    final cats = [
      const AudioCategoryModel(
          id: '', titleRu: 'Все', titleEn: 'All', description: '', icon: ''),
      ...kAudioCategories,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final selected = _category == cat.id;
          return GestureDetector(
            onTap: () => setState(() => _category = cat.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? SeeUColors.accent : c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: Text(
                cat.titleRu,
                style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : c.ink2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResults(SeeUThemeColors c) {
    if (!_hasInput) {
      return Center(
        child: SeeUEmptyState(
          icon: PhosphorIconsRegular.magnifyingGlass,
          title: 'Введите запрос',
          subtitle: 'Найдём треки, артистов и жанры',
        ),
      );
    }

    final async = ref.watch(audioSearchProvider(_params));
    return async.when(
      loading: () =>
          const SeeUListSkeleton(count: 8),
      error: (e, _) => SeeUErrorState(
        title: 'Не удалось выполнить поиск',
        onRetry: () => ref.invalidate(audioSearchProvider(_params)),
      ),
      data: (result) {
        if (result.tracks.isEmpty) {
          return SeeUEmptyState(
            icon: PhosphorIconsRegular.magnifyingGlass,
            title: 'Пока здесь нет треков',
            subtitle: _query.isNotEmpty
                ? 'По запросу «$_query» ничего не найдено'
                : 'В этой категории пока нет треков',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: result.tracks.length,
          itemBuilder: (_, i) =>
              _trackTile(result.tracks[i], result.tracks, c),
        );
      },
    );
  }

  Widget _trackTile(AudioTrack track, List<AudioTrack> queue, SeeUThemeColors c) {
    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.playing;

    return InkWell(
      onTap: () {
        if (isCurrent) {
          ref.read(miniPlayerProvider.notifier).toggle();
        } else {
          _playTrack(track, queue);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIconsRegular.musicNote,
                            color: c.ink3, size: 20),
                      ),
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
                    style: SeeUTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.displayArtist,
                    style: SeeUTypography.caption.copyWith(color: c.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (track.subcategory.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        track.category + (track.subcategory.isNotEmpty
                            ? ' · ${track.subcategory}'
                            : ''),
                        style: SeeUTypography.micro.copyWith(color: c.ink3),
                      ),
                    ),
                ],
              ),
            ),
            if (track.isLikedByMe)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                    PhosphorIcons.heart(PhosphorIconsStyle.fill),
                    color: SeeUColors.like,
                    size: 14),
              ),
            Text(
              track.durationFormatted,
              style: SeeUTypography.mono.copyWith(fontSize: 11, color: c.ink3),
            ),
            const SizedBox(width: 8),
            Icon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              color: isCurrent ? SeeUColors.accent : c.ink2,
              size: 28,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(PhosphorIconsRegular.dotsThreeVertical,
                  color: c.ink3, size: 18),
              onPressed: () => _showActions(track),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(AudioTrack track) {
    final c = context.seeuColors;
    showSeeUBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIconsRegular.musicNote, color: c.ink),
              title: Text(track.title,
                  style: SeeUTypography.subtitle
                      .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
              subtitle: Text(track.displayArtist,
                  style: SeeUTypography.caption.copyWith(color: c.ink2)),
            ),
            Divider(height: 1, thickness: 0.5, color: c.line),
            ListTile(
              leading: Icon(PhosphorIconsRegular.info, color: c.ink),
              title: Text('Подробнее',
                  style: SeeUTypography.body.copyWith(color: c.ink)),
              onTap: () {
                Navigator.pop(context);
                context.push('/music/track/${track.id}');
              },
            ),
          ],
        ),
      ),
    );
  }
}
