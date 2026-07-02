import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../core/audio/audio_player_service.dart';
import '../core/design/design.dart';
import '../core/models/audio_track.dart';
import '../core/providers/audio_provider.dart';
import '../core/providers/playlist_provider.dart';
import '../core/utils/format.dart';
import '../features/music/lyrics_screen.dart';
import '../features/music/queue_sheet.dart';
import 'audio_waveform.dart';

// ── Dark-context colours ─────────────────────────────────────────────────────
// The player floats over a blurred cover, so text/controls read on a dark
// backdrop. Centralised here instead of scattering `Colors.white*` literals.
const Color _kInk = Colors.white; // primary
const Color _kInk70 = Color(0xB3FFFFFF); // secondary
const Color _kInk54 = Color(0x8AFFFFFF); // tertiary / placeholder
const Color _kInk30 = Color(0x4DFFFFFF); // waveform inactive
const Color _kInk24 = Color(0x3DFFFFFF); // scrubber inactive track
const Color _kInk12 = Color(0x1FFFFFFF); // cover placeholder / disabled

/// Frosted glass control bar sitting over the cover — groups a cluster of
/// transport/utility controls into one glass surface (blur + highlight→tint
/// gradient + thin white border), mirroring the camera glass recipe.
class _GlassControlBar extends StatelessWidget {
  const _GlassControlBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.30),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(SeeURadii.card),
          ),
          child: child,
        ),
      ),
    );
  }
}

Future<void> showFullScreenPlayer(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: SeeUMotion.slow,
      reverseTransitionDuration: SeeUMotion.normal,
      pageBuilder: (_, __, ___) => const _FullScreenPlayerSheet(),
      transitionsBuilder: (_, anim, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: SeeUMotion.smooth)),
          child: child,
        );
      },
    ),
  );
}

class _FullScreenPlayerSheet extends ConsumerStatefulWidget {
  const _FullScreenPlayerSheet();

  @override
  ConsumerState<_FullScreenPlayerSheet> createState() =>
      _FullScreenPlayerSheetState();
}

class _FullScreenPlayerSheetState
    extends ConsumerState<_FullScreenPlayerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _coverPulse;
  bool _likeInFlight = false;
  bool _saveInFlight = false;

  @override
  void initState() {
    super.initState();
    _coverPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _coverPulse.dispose();
    super.dispose();
  }

  Future<void> _toggleLike(AudioTrack track) async {
    if (_likeInFlight) return;
    setState(() => _likeInFlight = true);
    final wasLiked = track.isLikedByMe;
    ref.read(miniPlayerProvider.notifier).setCurrentLiked(!wasLiked);
    try {
      final api = ref.read(apiClientProvider);
      if (wasLiked) {
        await api.delete(ApiEndpoints.audioTrackLike(track.id));
      } else {
        await api.post(ApiEndpoints.audioTrackLike(track.id));
      }
      ref.invalidate(audioFeedProvider);
    } catch (_) {
      ref.read(miniPlayerProvider.notifier).setCurrentLiked(wasLiked);
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось поставить лайк',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _likeInFlight = false);
    }
  }

  Future<void> _toggleSave(AudioTrack track) async {
    if (_saveInFlight) return;
    setState(() => _saveInFlight = true);
    final wasSaved = track.isSavedByMe;
    ref.read(miniPlayerProvider.notifier).setCurrentSaved(!wasSaved);
    try {
      final api = ref.read(apiClientProvider);
      if (wasSaved) {
        await api.delete(ApiEndpoints.audioTrackSave(track.id));
      } else {
        await api.post(ApiEndpoints.audioTrackSave(track.id));
      }
      ref.invalidate(savedTracksProvider);
    } catch (_) {
      ref.read(miniPlayerProvider.notifier).setCurrentSaved(wasSaved);
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось сохранить трек',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saveInFlight = false);
    }
  }

  void _addToPlaylist(BuildContext ctx, AudioTrack track) {
    showAddToPlaylistSheet(ctx, ref, track.id);
  }

  String _speedLabel(double speed) {
    if ((speed - speed.roundToDouble()).abs() < 0.001) {
      return '${speed.toStringAsFixed(0)}x';
    }
    var s = speed.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return '${s}x';
  }

  void _showSpeedPicker(BuildContext ctx, double current) {
    HapticFeedback.selectionClick();
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final c = ctx.seeuColors;
    showSeeUBottomSheet<void>(
      context: ctx,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(PhosphorIcons.gauge(), color: SeeUColors.accent),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('СКОРОСТЬ',
                          style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                      const SizedBox(height: 2),
                      Text('Воспроизведение',
                          style: SeeUTypography.displayS.copyWith(color: c.ink)),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: c.line),
            ...speeds.map((s) {
              final selected = (current - s).abs() < 0.01;
              return ListTile(
                title: Text(
                  s == 1.0 ? 'Обычная (1x)' : _speedLabel(s),
                  style: TextStyle(
                    color: selected ? SeeUColors.accent : c.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: selected
                    ? Icon(PhosphorIcons.check(), color: SeeUColors.accent)
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(miniPlayerProvider.notifier).setSpeed(s);
                  Navigator.of(sheetCtx).pop();
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch only the fields the chrome/cover/controls need — NOT position or
    // duration. Those tick ~5x/sec and are isolated into the [_PositionSection]
    // leaf below, so the expensive blurred backdrop no longer repaints on every
    // position update.
    final track = ref.watch(miniPlayerProvider.select((s) => s.track));
    final playing = ref.watch(miniPlayerProvider.select((s) => s.playing));
    final shuffle = ref.watch(miniPlayerProvider.select((s) => s.shuffle));
    final repeat = ref.watch(miniPlayerProvider.select((s) => s.repeat));
    final speed = ref.watch(miniPlayerProvider.select((s) => s.speed));
    final hasQueue = ref.watch(miniPlayerProvider.select((s) => s.hasQueue));
    final hasNext = ref.watch(miniPlayerProvider.select((s) => s.hasNext));
    final queueIndex = ref.watch(miniPlayerProvider.select((s) => s.queueIndex));
    final queueLength =
        ref.watch(miniPlayerProvider.select((s) => s.queue.length));
    final notifier = ref.read(miniPlayerProvider.notifier);

    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    return SwipeToDismiss(
      downOnly: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Backdrop — blurred cover
            Positioned.fill(
              child: track.coverUrl.isNotEmpty
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          decoration: const BoxDecoration(
                            gradient: SeeUGradients.heroOrange,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: SeeUGradients.heroOrange,
                      ),
                    ),
            ),
            // Dark overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.80),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Свернуть',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(PhosphorIcons.caretDown(),
                                color: _kInk),
                          ),
                          const Spacer(),
                          Text(
                            (hasQueue
                                    ? '${queueIndex + 1} / $queueLength'
                                    : 'Сейчас играет')
                                .toUpperCase(),
                            style: SeeUTypography.kicker.copyWith(
                              color: _kInk70,
                            ),
                          ),
                          const Spacer(),
                          // More actions
                          PopupMenuButton<String>(
                            icon: Icon(PhosphorIcons.dotsThreeVertical(),
                                color: _kInk70),
                            color: Colors.black87,
                            onSelected: (v) async {
                              if (v == 'playlist') {
                                _addToPlaylist(context, track);
                                return;
                              }
                              if (v == 'detail') {
                                final router = GoRouter.of(context);
                                await Navigator.of(context).maybePop();
                                router.push('/music/track/${track.id}');
                                return;
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'playlist',
                                child: Row(children: [
                                  Icon(PhosphorIcons.queue(),
                                      color: Colors.white70, size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Добавить в плейлист',
                                      style: TextStyle(color: Colors.white)),
                                ]),
                              ),
                              if (track.usesCount > 0)
                                PopupMenuItem(
                                  value: 'detail',
                                  child: Row(children: [
                                    Icon(PhosphorIcons.filmStrip(),
                                        color: Colors.white70, size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Видео с этим звуком (${track.usesCount})',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Large cover with pulse animation
                    Expanded(
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _coverPulse,
                          builder: (_, child) {
                            final t =
                                SeeUMotion.breathe.transform(_coverPulse.value);
                            final scale = playing ? 0.97 + 0.03 * t : 0.96;
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: track.coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: track.coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) =>
                                          Container(color: _kInk12),
                                      errorWidget: (_, __, ___) => Container(
                                        decoration: const BoxDecoration(
                                          gradient: SeeUGradients.heroOrange,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      decoration: const BoxDecoration(
                                        gradient: SeeUGradients.heroOrange,
                                      ),
                                      child: const Icon(
                                        PhosphorIconsRegular.musicNote,
                                        color: _kInk54,
                                        size: 80,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Title + artist row with like/save
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeeUTypography.displayM.copyWith(
                                    color: _kInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.displayArtist.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeeUTypography.kicker.copyWith(
                                    color: _kInk70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Like button
                          _ActionBtn(
                            icon: track.isLikedByMe
                                ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                                : PhosphorIcons.heart(),
                            color: track.isLikedByMe
                                ? SeeUColors.like
                                : Colors.white70,
                            loading: _likeInFlight,
                            onTap: () => _toggleLike(track),
                          ),
                          const SizedBox(width: 4),
                          // Save button
                          _ActionBtn(
                            icon: track.isSavedByMe
                                ? PhosphorIcons.bookmarkSimple(
                                    PhosphorIconsStyle.fill)
                                : PhosphorIcons.bookmarkSimple(),
                            color: track.isSavedByMe
                                ? SeeUColors.accent
                                : Colors.white70,
                            loading: _saveInFlight,
                            onTap: () => _toggleSave(track),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Waveform + scrubber + time labels — isolated leaf that
                    // watches only position/duration, so per-tick updates don't
                    // rebuild the blurred backdrop or cover above.
                    _PositionSection(track: track),
                    const SizedBox(height: 16),

                    // Shuffle / Prev / Play-Pause / Next / Repeat — один
                    // стеклянный бар-кластер над обложкой (рецепт камеры).
                    _GlassControlBar(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Shuffle
                        _IconBtn(
                          icon: PhosphorIcons.shuffle(
                            shuffle
                                ? PhosphorIconsStyle.fill
                                : PhosphorIconsStyle.regular,
                          ),
                          onTap: hasQueue
                              ? () {
                                  HapticFeedback.selectionClick();
                                  notifier.toggleShuffle();
                                }
                              : null,
                          size: 24,
                          activeColor: shuffle ? SeeUColors.accent : null,
                        ),
                        _IconBtn(
                          icon: PhosphorIcons.skipBack(PhosphorIconsStyle.fill),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            notifier.previous();
                          },
                          size: 28,
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            notifier.toggle();
                          },
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SeeUGradients.heroOrange,
                              boxShadow: [
                                BoxShadow(
                                  color: SeeUColors.accent.withValues(alpha: 0.5),
                                  blurRadius: 26,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                playing
                                    ? PhosphorIcons.pause(
                                        PhosphorIconsStyle.fill)
                                    : PhosphorIcons.play(PhosphorIconsStyle.fill),
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                        _IconBtn(
                          icon: PhosphorIcons.skipForward(PhosphorIconsStyle.fill),
                          onTap: hasNext
                              ? () {
                                  HapticFeedback.lightImpact();
                                  notifier.next();
                                }
                              : null,
                          size: 28,
                        ),
                        // Repeat — cycles off / all / one
                        _IconBtn(
                          icon: repeat == PlayerRepeatMode.one
                              ? PhosphorIcons.repeatOnce()
                              : PhosphorIcons.repeat(),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.cycleRepeat();
                          },
                          size: 24,
                          activeColor: repeat == PlayerRepeatMode.off
                              ? null
                              : SeeUColors.accent,
                        ),
                      ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Speed / Lyrics / Queue / Playlist / Stop — второй
                    // стеклянный бар utility-действий.
                    _GlassControlBar(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _UtilityBtn(
                          icon: PhosphorIcons.gauge(),
                          label: _speedLabel(speed),
                          highlight: (speed - 1.0).abs() > 0.01,
                          onTap: () => _showSpeedPicker(context, speed),
                        ),
                        _UtilityBtn(
                          icon: PhosphorIcons.microphoneStage(),
                          label: 'Текст',
                          onTap: () => showLyricsScreen(context),
                        ),
                        _UtilityBtn(
                          icon: PhosphorIcons.listBullets(),
                          label: 'Очередь',
                          onTap: () => showQueueSheet(context),
                        ),
                        _UtilityBtn(
                          icon: PhosphorIcons.queue(),
                          label: 'Плейлист',
                          onTap: () => _addToPlaylist(context, track),
                        ),
                        _UtilityBtn(
                          icon: PhosphorIcons.stop(),
                          label: 'Стоп',
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final nav = Navigator.of(context);
                            await notifier.close();
                            if (mounted) nav.maybePop();
                          },
                        ),
                      ],
                      ),
                    ),
                    const SizedBox(height: 10),
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

/// Waveform + scrubber + time labels. A leaf [ConsumerStatefulWidget] so it can
/// own the in-progress scrub state AND watch only `position`/`duration` (which
/// tick ~5x/sec) — keeping the per-tick rebuild off the blurred backdrop, the
/// cover, and the transport controls in the parent sheet.
class _PositionSection extends ConsumerStatefulWidget {
  const _PositionSection({required this.track});

  final AudioTrack track;

  @override
  ConsumerState<_PositionSection> createState() => _PositionSectionState();
}

class _PositionSectionState extends ConsumerState<_PositionSection> {
  double? _scrubbing;
  String? _scrubTrackId; // track being scrubbed — guards against auto-advance

  @override
  void didUpdateWidget(covariant _PositionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the track changed mid-drag (e.g. gapless auto-advance), abandon the
    // in-progress scrub so we never seek the new track to the old position.
    if (_scrubbing != null && _scrubTrackId != widget.track.id) {
      _scrubbing = null;
      _scrubTrackId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final notifier = ref.read(miniPlayerProvider.notifier);
    final pos = ref.watch(miniPlayerProvider.select((s) => s.position));
    final dur =
        ref.watch(miniPlayerProvider.select((s) => s.duration)) ?? Duration.zero;

    final maxMs = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final liveMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final shownMs = _scrubbing ?? liveMs;
    final shownDuration =
        Duration(milliseconds: shownMs.round().clamp(0, dur.inMilliseconds));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Waveform (Phase 9) — hidden when no data, no height change.
        if (track.waveformData != null && track.waveformData!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AudioWaveformPreview(
              waveform: track.waveformData,
              progress: maxMs > 1 ? liveMs / maxMs : 0.0,
              height: 36,
              activeColor: SeeUColors.accent,
              inactiveColor: _kInk30,
            ),
          ),

        // Scrubber
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: SeeUColors.accent,
            inactiveTrackColor: _kInk24,
            thumbColor: Colors.white,
            overlayColor: SeeUColors.accent.withValues(alpha: 0.18),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: shownMs.clamp(0.0, maxMs),
            max: maxMs,
            onChangeStart: (v) => setState(() {
              _scrubbing = v;
              _scrubTrackId = track.id;
            }),
            onChanged: (v) => setState(() => _scrubbing = v),
            onChangeEnd: (v) async {
              // Only seek if we're still on the track we started scrubbing
              // (guards against mid-drag auto-advance).
              if (_scrubTrackId == track.id) {
                await notifier.seek(Duration(milliseconds: v.round()));
              }
              if (mounted) {
                setState(() {
                  _scrubbing = null;
                  _scrubTrackId = null;
                });
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shownDuration),
                  style: SeeUTypography.caption
                      .copyWith(color: Colors.white70, fontSize: 12)),
              Text(
                dur.inMilliseconds > 0
                    ? '-${formatDuration(dur - shownDuration)}'
                    : '0:00',
                style: SeeUTypography.caption
                    .copyWith(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Playlist picker bottom sheet ─────────────────────────────────────────────

/// Show a bottom sheet that lets the user pick a playlist to add [trackId] to.
/// Reusable from player, track detail, and track cards.
void showAddToPlaylistSheet(BuildContext context, WidgetRef ref, String trackId) {
  final c = context.seeuColors;
  showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Consumer(
      builder: (_, ref, __) {
        final playlistsAsync = ref.watch(myPlaylistsProvider);
        final playlists = playlistsAsync.value ?? const [];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.queue(), color: SeeUColors.accent),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('МУЗЫКА',
                              style: SeeUTypography.kicker
                                  .copyWith(color: c.ink3)),
                          const SizedBox(height: 2),
                          Text('Добавить в плейлист',
                              style: SeeUTypography.displayS
                                  .copyWith(color: c.ink)),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.line),
                ListTile(
                  leading: Icon(PhosphorIcons.plus(), color: SeeUColors.accent),
                  title: const Text('Создать новый плейлист'),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _createAndAddToPlaylist(context, ref, trackId);
                  },
                ),
                Divider(height: 1, color: c.line),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Нет плейлистов. Создайте первый.'),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (_, i) {
                        final p = playlists[i];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: p.coverUrl.isNotEmpty
                                  ? Image.network(p.coverUrl, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(color: c.surface2))
                                  : Container(color: c.surface2,
                                      child: Icon(PhosphorIcons.musicNotesSimple(),
                                          color: c.ink3, size: 18)),
                            ),
                          ),
                          title: Text(p.name),
                          subtitle: Text('${p.tracksCount} треков',
                              style: TextStyle(color: c.ink3, fontSize: 11)),
                          onTap: () async {
                            Navigator.pop(sheetCtx);
                            final ok = await ref
                                .read(myPlaylistsProvider.notifier)
                                .addTrack(p.id, trackId);
                            if (context.mounted) {
                              showSeeUSnackBar(
                                context,
                                ok
                                    ? 'Добавлено в «${p.name}»'
                                    : 'Не удалось добавить в плейлист',
                                icon: PhosphorIcons.queue(),
                                tone: ok
                                    ? SeeUTone.success
                                    : SeeUTone.danger,
                              );
                            }
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

Future<void> _createAndAddToPlaylist(
    BuildContext context, WidgetRef ref, String trackId) async {
  final ctrl = TextEditingController();
  final name = await showSeeUBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final c = sheetCtx.seeuColors;
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('МУЗЫКА',
                style: SeeUTypography.kicker.copyWith(color: c.ink3)),
            const SizedBox(height: 2),
            Text('Новый плейлист',
                style: SeeUTypography.displayS.copyWith(color: c.ink)),
            const SizedBox(height: 16),
            SeeUInput(
              controller: ctrl,
              hintText: 'Название',
              autofocus: true,
              onSubmitted: (v) => Navigator.of(sheetCtx).pop(v.trim()),
            ),
            const SizedBox(height: 16),
            SeeUButton(
              label: 'Создать',
              onTap: () => Navigator.of(sheetCtx).pop(ctrl.text.trim()),
            ),
          ],
        ),
      );
    },
  );
  if (name == null || name.isEmpty) return;
  final notifier = ref.read(myPlaylistsProvider.notifier);
  final p = await notifier.create(name);
  if (p == null) {
    if (context.mounted) {
      showSeeUSnackBar(context, 'Не удалось создать плейлист',
          tone: SeeUTone.danger);
    }
    return;
  }
  final ok = await notifier.addTrack(p.id, trackId);
  if (context.mounted) {
    showSeeUSnackBar(
      context,
      ok
          ? 'Создан «${p.name}» и трек добавлен'
          : 'Плейлист создан, трек не добавился',
      icon: PhosphorIcons.queue(),
      tone: ok ? SeeUTone.success : SeeUTone.danger,
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kInk54,
                  ),
                ),
              )
            : Icon(icon, color: color, size: 26),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? activeColor;
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.size = 28,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? Colors.white24
        : (activeColor ?? Colors.white);
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      icon: Icon(icon, color: color),
    );
  }
}

/// Compact labelled icon button used in the utility row (speed/lyrics/queue…).
class _UtilityBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _UtilityBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? SeeUColors.accent : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
