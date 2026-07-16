import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/playlist_provider.dart';
import 'audio_design.dart';
import 'moment_sheet.dart';
import 'music_search_screen.dart' show AudioErrorState;

final _trackDetailProvider =
    FutureProvider.autoDispose.family<AudioTrack, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.audioTrackById(id));
  final data =
      r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  return AudioTrack.fromJson(data as Map<String, dynamic>);
});

/// Карточка трека — один каркас, разный порядок блоков по режиму.
///
/// У песни герой — волна и лайк, техданные и происхождение спрятаны вниз.
/// У мема сценарий другой: он вообще не открывает эту простыню, а показывает
/// шторку с петлёй и «Взять в видео» — за три секунды всё уже слышно.
class TrackDetailScreen extends ConsumerStatefulWidget {
  final String trackId;
  const TrackDetailScreen({super.key, required this.trackId});

  @override
  ConsumerState<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends ConsumerState<TrackDetailScreen> {
  bool? _liked;
  bool? _saved;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_trackDetailProvider(widget.trackId));

    return Scaffold(
      backgroundColor: c.bg,
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: SeeUColors.accent),
        ),
        error: (_, __) => SafeArea(
          child: Column(
            children: [
              _bar(context, null),
              Expanded(
                child: AudioErrorState(
                  onRetry: () =>
                      ref.invalidate(_trackDetailProvider(widget.trackId)),
                ),
              ),
            ],
          ),
        ),
        data: (track) {
          // Мем открывается шторкой: экран-простыня ему не нужен.
          if (modeOf(track) == ListenMode.moment) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!context.mounted) return;
              context.pop();
              await showMomentSheet(context, track);
            });
            return const SizedBox.shrink();
          }
          return _body(track);
        },
      ),
    );
  }

  Widget _body(AudioTrack t) {
    final c = context.seeuColors;
    final mode = modeOf(t);
    final cat = findCategory(t.category);
    final liked = _liked ?? t.isLikedByMe;
    final saved = _saved ?? t.isSavedByMe;

    final player = ref.watch(miniPlayerProvider);
    final isCurrent = player.track?.id == t.id;
    final progress = isCurrent && (player.duration?.inMilliseconds ?? 0) > 0
        ? player.position.inMilliseconds / player.duration!.inMilliseconds
        : (t.durationSeconds > 0
            ? t.positionSeconds / t.durationSeconds
            : 0.0);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: 24 + context.bottomBarInset),
        children: [
          _bar(context, t),

          // Обложка
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (_, box) => TrackCover(
                    track: t,
                    size: box.maxWidth,
                    radius: 22,
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161310).withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mode.icon, size: 12, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          [
                            cat?.title ?? '',
                            if (t.subcategory.isNotEmpty) t.subcategory,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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

          // Название и автор
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 28,
                    height: 1.05,
                    color: c.ink,
                  ),
                ),
                if (t.artist.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // Автор — строка, не сущность: тап ведёт в поиск по имени.
                  Tappable(
                    onTap: () => context.push(
                        '/music/search?q=${Uri.encodeComponent(t.artist)}'),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, color: c.ink2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(PhosphorIcons.magnifyingGlass(),
                            size: 12, color: c.ink3),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Счётчики
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                _counter(c, PhosphorIconsFill.playCircle, c.ink3,
                    formatCount(t.playsCount)),
                _counter(c, PhosphorIconsFill.heart, SeeUColors.like,
                    formatCount(t.likesCount)),
                if (t.usesCount > 0)
                  _counter(c, PhosphorIconsFill.video, c.ink3,
                      '${formatCount(t.usesCount)} видео'),
              ],
            ),
          ),

          // Волна и play — герой карточки песни.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Tappable.scaled(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (isCurrent) {
                      ref.read(miniPlayerProvider.notifier).toggle();
                    } else {
                      ref.read(miniPlayerProvider.notifier).playWithQueue(
                            track: t,
                            queue: [t],
                            index: 0,
                            source: 'detail',
                          );
                    }
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mode.color,
                      boxShadow: [
                        BoxShadow(
                          color: mode.color.withValues(alpha: 0.65),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                          spreadRadius: -8,
                        ),
                      ],
                    ),
                    child: Icon(
                      isCurrent && player.playing
                          ? PhosphorIconsFill.pause
                          : PhosphorIconsFill.play,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      TrackWaveform(
                        peaks: t.waveformData,
                        progress: progress.clamp(0.0, 1.0),
                        color: mode.color,
                        height: 60,
                        onSeek: isCurrent
                            ? (f) {
                                final total = player.duration ??
                                    Duration(seconds: t.durationSeconds);
                                ref.read(miniPlayerProvider.notifier).seek(
                                      Duration(
                                        milliseconds:
                                            (total.inMilliseconds * f).round(),
                                      ),
                                    );
                              }
                            : null,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            // У недослушанной книги честнее показать, где ты
                            // остановился, а не «0:00».
                            mode.resumable && t.positionSeconds > 0
                                ? formatDuration(t.positionSeconds)
                                : '0:00',
                            style: TextStyle(fontSize: 11, color: c.ink3),
                          ),
                          Text(
                            formatDuration(t.durationSeconds),
                            style: TextStyle(fontSize: 11, color: c.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Действия
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Row(
              children: [
                _action(
                  c,
                  icon: liked
                      ? PhosphorIconsFill.heart
                      : PhosphorIconsRegular.heart,
                  label: 'Лайк',
                  color: liked ? SeeUColors.like : c.ink2,
                  bg: liked ? SeeUColors.like.withValues(alpha: 0.12) : null,
                  onTap: () => _toggleLike(t, liked),
                ),
                _action(
                  c,
                  icon: saved
                      ? PhosphorIconsFill.bookmarkSimple
                      : PhosphorIconsRegular.bookmarkSimple,
                  label: 'Сохранить',
                  color: saved ? SeeUColors.accent : c.ink2,
                  bg: saved
                      ? SeeUColors.accent.withValues(alpha: 0.12)
                      : null,
                  onTap: () => _toggleSave(t, saved),
                ),
                _action(
                  c,
                  icon: PhosphorIconsRegular.plus,
                  label: 'В плейлист',
                  color: c.ink2,
                  onTap: () => _addToPlaylist(t),
                ),
                _action(
                  c,
                  icon: PhosphorIconsRegular.videoCamera,
                  label: 'В видео',
                  color: c.ink2,
                  onTap: () => context.push('/post/create', extra: t),
                ),
              ],
            ),
          ),

          // Подвал: то, что нужно раз в жизни.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.album.isNotEmpty) _meta(c, 'Альбом', t.album),
                if (t.mood.isNotEmpty) _meta(c, 'Настроение', t.mood),
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.description,
                    style:
                        TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
                  ),
                ],
                if (t.technicalSummary.isNotEmpty || t.sizeFormatted.isNotEmpty)
                  _meta(
                    c,
                    'Файл',
                    [t.technicalSummary, t.sizeFormatted]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                  ),
                if (t.isOriginalSound)
                  _meta(c, 'Происхождение', 'Оригинальный звук из видео'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Шапка ─────────────────────────────────────────────────────────────────

  Widget _bar(BuildContext context, AudioTrack? t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Row(
        children: [
          AudioSquareButton(
            icon: PhosphorIcons.arrowLeft(),
            onTap: () => context.pop(),
          ),
          const Spacer(),
          if (t != null)
            AudioSquareButton(
              icon: PhosphorIcons.shareNetwork(),
              onTap: () => Share.share(
                '${t.title}${t.artist.isNotEmpty ? ' — ${t.artist}' : ''}'
                '\n\nseeu://track/${t.id}',
                subject: t.title,
              ),
            ),
        ],
      ),
    );
  }

  // ── Мелочи ────────────────────────────────────────────────────────────────

  Widget _counter(SeeUThemeColors c, IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 12.5, color: c.ink3)),
      ],
    );
  }

  Widget _action(
    SeeUThemeColors c, {
    required IconData icon,
    required String label,
    required Color color,
    Color? bg,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Tappable.scaled(
        onTap: _busy ? null : onTap,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: bg ?? c.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(fontSize: 10, color: c.ink3)),
          ],
        ),
      ),
    );
  }

  Widget _meta(SeeUThemeColors c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.ink2,
          ),
          children: [
            TextSpan(
              text: '· $value',
              style: TextStyle(fontWeight: FontWeight.w400, color: c.ink3),
            ),
          ],
        ),
      ),
    );
  }

  // ── Действия ──────────────────────────────────────────────────────────────

  Future<void> _toggleLike(AudioTrack t, bool liked) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _liked = !liked;
    });
    HapticFeedback.lightImpact();
    try {
      final api = ref.read(apiClientProvider);
      if (!liked) {
        await api.post(ApiEndpoints.audioTrackLike(t.id));
      } else {
        await api.delete(ApiEndpoints.audioTrackLike(t.id));
      }
      ref.read(miniPlayerProvider.notifier).setCurrentLiked(!liked);
    } catch (_) {
      if (mounted) setState(() => _liked = liked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSave(AudioTrack t, bool saved) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _saved = !saved;
    });
    HapticFeedback.lightImpact();
    try {
      final api = ref.read(apiClientProvider);
      if (!saved) {
        await api.post(ApiEndpoints.audioTrackSave(t.id));
      } else {
        await api.delete(ApiEndpoints.audioTrackSave(t.id));
      }
      ref.read(miniPlayerProvider.notifier).setCurrentSaved(!saved);
    } catch (_) {
      if (mounted) setState(() => _saved = saved);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Чек-лист плейлистов, а не «выберите из списка»: жмёшь — отмечено.
  Future<void> _addToPlaylist(AudioTrack t) async {
    final lists = ref.read(myPlaylistsProvider).valueOrNull ?? const [];

    await showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
                child: Text(
                  'В плейлист',
                  style: SeeUTypography.displayS
                      .copyWith(fontSize: 22, color: c.ink),
                ),
              ),
              if (lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                  child: Text(
                    'Плейлистов пока нет — создай первый в разделе «Моё».',
                    style: TextStyle(fontSize: 13.5, color: c.ink3),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in lists)
                        ListTile(
                          leading: Icon(PhosphorIcons.playlist(),
                              color: SeeUColors.accent),
                          title: Text(
                            p.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: c.ink),
                          ),
                          subtitle: Text(
                            '${p.tracksCount}',
                            style: TextStyle(color: c.ink3),
                          ),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final ok = await ref
                                .read(myPlaylistsProvider.notifier)
                                .addTrack(p.id, t.id);
                            if (!mounted) return;
                            showSeeUSnackBar(
                              context,
                              ok
                                  ? 'Добавлено в «${p.name}»'
                                  : 'Не удалось добавить',
                              tone: ok ? SeeUTone.success : SeeUTone.danger,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
