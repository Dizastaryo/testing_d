import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_discovery_provider.dart';
import '../../core/providers/audio_provider.dart';
import 'audio_design.dart';
import 'widgets/track_row.dart';

/// Главная Аудиотеки — «Слушать».
///
/// Иерархия вместо ленты равновесных каруселей. 90% времени человек хочет
/// продолжить начатое или включить что-то на сейчас, поэтому порядок:
/// **Твой день → Продолжить → Категории → Набирают**. Сохранённое, плейлисты,
/// загрузки и звуки из видео уехали в «Моё» и «Поиск»: главная отвечает на
/// вопрос «что послушать сейчас», а не «где мои вещи».
class MusicScreen extends ConsumerWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AudioMainBar(title: 'Слушать'),
            Expanded(
              child: RefreshIndicator(
                color: SeeUColors.accent,
                onRefresh: () async {
                  ref.invalidate(audioDiscoveryProvider);
                  ref.invalidate(continueListeningProvider);
                  ref.invalidate(trendingTracksProvider);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      0, 16, 0, 24 + context.bottomBarInset),
                  // Категории уехали на вкладку «Поиск» (там их место) —
                  // раньше они дублировались тут, и Главная с Поиском выглядели
                  // одинаково. Главная теперь чисто «слушать сейчас».
                  children: const [
                    _SearchField(),
                    SizedBox(height: 18),
                    _DailyMixHero(),
                    _ContinueBlock(),
                    _TrendingBlock(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Поиск ──────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Tappable.scaled(
        onTap: () => context.go('/music/search'),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(PhosphorIcons.magnifyingGlass(), size: 18, color: c.ink3),
              const SizedBox(width: 10),
              Text(
                'Трек, автор или звук',
                style: TextStyle(fontSize: 14, color: c.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── «Твой день» ────────────────────────────────────────────────────────────

/// Hero — ответ на «что послушать прямо сейчас». Тап запускает микс целиком.
class _DailyMixHero extends ConsumerStatefulWidget {
  const _DailyMixHero();

  @override
  ConsumerState<_DailyMixHero> createState() => _DailyMixHeroState();
}

class _DailyMixHeroState extends ConsumerState<_DailyMixHero> {
  List<AudioTrack>? _tracks;
  bool _loading = true;
  // Когда микс собрался — для подписи «собрано в HH:MM» (§Главная).
  DateTime? _loadedAt;

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
      final data = r.data['data'];
      final list = data is List ? data : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _tracks = list
            .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadedAt = DateTime.now();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static const _weekdays = [
    'ПОНЕДЕЛЬНИК',
    'ВТОРНИК',
    'СРЕДА',
    'ЧЕТВЕРГ',
    'ПЯТНИЦА',
    'СУББОТА',
    'ВОСКРЕСЕНЬЕ',
  ];

  /// Имя микса — от времени суток. Честнее, чем выдуманное название.
  String get _title {
    final h = DateTime.now().hour;
    if (h < 11) return 'Тёплый старт';
    if (h < 17) return 'Дневной ход';
    if (h < 23) return 'Вечерний свет';
    return 'Поздняя тишина';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: context.seeuColors.line,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    }

    final tracks = _tracks ?? const <AudioTrack>[];
    if (tracks.isEmpty) return const SizedBox.shrink();

    final player = ref.watch(miniPlayerProvider);
    // «Тот же микс сейчас в плеере» (даже на паузе и после автоперехода на
    // трек k>0) — тогда тап это пауза/продолжить, а не пересборка с нуля.
    // Раньше условие включало player.playing, и пауза на середине приводила к
    // рестарту всего микса с первого трека.
    final isCurrentMix =
        player.queueSource == 'daily_mix' && player.track != null;
    final isThisMix = isCurrentMix && player.playing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Tappable.scaled(
        onTap: () {
          if (isCurrentMix) {
            ref.read(miniPlayerProvider.notifier).toggle();
          } else {
            ref.read(miniPlayerProvider.notifier).playWithQueue(
                  track: tracks.first,
                  queue: tracks,
                  index: 0,
                  source: 'daily_mix',
                );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeeUColors.accent,
                SeeUColors.accentSecondary,
                SeeUColors.amber,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.6),
                blurRadius: 34,
                offset: const Offset(0, 18),
                spreadRadius: -16,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ТВОЙ ДЕНЬ · ${_weekdays[DateTime.now().weekday - 1]}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _title,
                      style: SeeUTypography.displayS.copyWith(
                        fontSize: 30,
                        height: 1.02,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loadedAt != null
                          ? '${tracks.length} ${_tracksWord(tracks.length)} · собрано в ${_loadedAt!.hour}:${_loadedAt!.minute.toString().padLeft(2, '0')}'
                          : '${tracks.length} ${_tracksWord(tracks.length)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Волна первого трека микса — настоящая, если пики есть.
                    // §C: ширина 74% карточки (не фиксированные 190).
                    FractionallySizedBox(
                      widthFactor: 0.74,
                      alignment: Alignment.centerLeft,
                      child: TrackWaveform(
                        peaks: tracks.first.waveformData,
                        progress: 0.34,
                        color: Colors.white,
                        height: 32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: Icon(
                  isThisMix ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
                  size: 26,
                  color: SeeUColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _tracksWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'треков';
    if (m10 == 1) return 'трек';
    if (m10 >= 2 && m10 <= 4) return 'трека';
    return 'треков';
  }
}

// ─── «Продолжить» ───────────────────────────────────────────────────────────

/// Недослушанные книги и подкасты. Блока нет, пока продолжать нечего.
class _ContinueBlock extends ConsumerWidget {
  const _ContinueBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(continueListeningProvider).valueOrNull ?? const [];
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        const _SectionHeader(title: 'Продолжить'),
        const SizedBox(height: 14),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ContinueCard(track: tracks[i]),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  final AudioTrack track;
  const _ContinueCard({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final mode = modeOf(track);

    return Tappable.scaled(
      onTap: () => ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: track,
            queue: [track],
            index: 0,
            source: 'continue',
          ),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            TrackCover(track: track, size: 48, radius: 10),
            const SizedBox(width: 10),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRemaining(track.remainingSeconds),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: track.listenedFraction,
                      minHeight: 4,
                      backgroundColor: mode.color.withValues(alpha: 0.16),
                      valueColor: AlwaysStoppedAnimation(mode.color),
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
}

// ─── «Набирают» ─────────────────────────────────────────────────────────────

class _TrendingBlock extends ConsumerWidget {
  const _TrendingBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(trendingTracksProvider).valueOrNull ?? const [];
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        const _SectionHeader(title: 'Набирают'),
        const SizedBox(height: 12),
        for (var i = 0; i < tracks.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: TrackRow(
              track: tracks[i],
              queue: tracks,
              index: i,
              source: 'trending',
            ),
          ),
      ],
    );
  }
}

// ─── Заголовок секции ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title,
            style: SeeUTypography.displayS.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: c.line)),
        ],
      ),
    );
  }
}
