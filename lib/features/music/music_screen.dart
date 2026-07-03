import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/audio_discovery_provider.dart';
import '../../core/providers/audio_provider.dart';
import 'widgets/categories_grid.dart';
import 'widgets/daily_mix_card.dart';
import 'widgets/discovery_carousel.dart';
import 'widgets/my_uploads_section.dart';
import 'widgets/now_playing_friends_row.dart';
import 'widgets/original_sounds_section.dart';
import 'widgets/playlists_strip.dart';
import 'widgets/quick_button.dart';
import 'widgets/trending_section.dart';
import 'widgets/video_sounds_section.dart';

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
            const SliverToBoxAdapter(child: NowPlayingFriendsRow()),
            // Recently played — only shown if backend returns data.
            // Must be a sliver at every state (loading, error, empty, data).
            discovery.when(
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.recentlyPlayed.isNotEmpty
                  ? SliverToBoxAdapter(
                      child: DiscoveryTrackCarousel(
                        title: 'Продолжить',
                        kicker: 'НЕДАВНЕЕ',
                        tracks: d.recentlyPlayed,
                        source: 'recently_played',
                      ),
                    )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            const SliverToBoxAdapter(child: DailyMixCard()),
            // Trending from discovery — ranked list
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.trendingTracks.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: TrendingSection(tracks: d.trendingTracks),
                    ),
            ),
            // Categories grid
            const SliverToBoxAdapter(child: CategoriesGrid()),
            // Original sounds — sounds extracted from videos
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.originalSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: OriginalSoundsSection(tracks: d.originalSounds),
                    ),
            ),
            // Video sounds — cards with Использовать CTA
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.videoSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: VideoSoundsSection(tracks: d.videoSounds),
                    ),
            ),
            // Meme sounds
            discovery.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (d) => d.memeSounds.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(
                      child: DiscoveryTrackCarousel(
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
                      child: DiscoveryTrackCarousel(
                        title: 'Новинки',
                        kicker: 'СВЕЖЕЕ',
                        tracks: d.newTracks,
                        source: 'new_tracks',
                      ),
                    ),
            ),
            const SliverToBoxAdapter(child: PlaylistsStrip()),
            const SliverToBoxAdapter(child: MyUploadsSection()),
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

  // A8: та же glass-обработка, что у _buildGlassHeader ленты (blur 28 +
  // градиент white 0.10→0.14 / surface 0.72 + hairline), но НЕ pinned —
  // это обычный sliver в CustomScrollView, поэтому уезжает при скролле.
  Widget _buildHeader(ThemeData theme, SeeUThemeColors c) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                c.surface.withValues(alpha: 0.72),
              ],
            ),
            border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.of(context).padding.top + 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'АУДИОТЕКА',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.accent, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              Text(
                'Аудиотека',
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
                    child: QuickButton(
                      icon: PhosphorIcons.uploadSimple(),
                      label: 'Загрузить',
                      onTap: () async {
                        await context.push('/music/upload');
                        ref.invalidate(audioDiscoveryProvider);
                        ref.invalidate(myTracksProvider);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: QuickButton(
                      icon: PhosphorIcons.musicNote(),
                      label: 'Мои треки',
                      onTap: () => context.push('/music/mine'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: QuickButton(
                      icon: PhosphorIcons.bookmarkSimple(),
                      label: 'Сохранённые',
                      onTap: () => context.push('/music/saved'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: QuickButton(
                      icon: PhosphorIcons.queue(),
                      label: 'Плейлисты',
                      onTap: () => openPlaylistsSheet(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
