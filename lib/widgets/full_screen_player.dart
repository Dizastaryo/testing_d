import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/audio/audio_player_service.dart';
import '../core/design/design.dart';

/// Full-screen player. Раскрывается при тапе на mini-player'е через
/// `Navigator.push(showFullScreenPlayer(...))`. Большая обложка (с лёгкой
/// scale-анимацией при play), scrubber с seek'ом, play/pause primary,
/// закрытие свайпом-вниз.
///
/// Mini-player'ом управляет тот же `miniPlayerProvider`, поэтому full-screen
/// и mini синхронизированы — закрыл full, mini остаётся в работе.
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
  // Если юзер тащит slider — игнорируем поток positionStream до отпускания.
  double? _scrubbing;

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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(miniPlayerProvider);
    final track = state.track;
    final notifier = ref.read(miniPlayerProvider.notifier);

    if (track == null) {
      // Случай: трек закрыт где-то ещё — закрываем full-screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final dur = state.duration ?? Duration.zero;
    final pos = state.position;
    final maxMs = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final liveMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final shownMs = _scrubbing ?? liveMs;
    final shownDuration =
        Duration(milliseconds: shownMs.round().clamp(0, dur.inMilliseconds));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Backdrop — размытая обложка на весь экран
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
          // Затемняющий overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // Контент
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Top bar: handle + close
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Свернуть',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(PhosphorIcons.caretDown(),
                              color: Colors.white),
                        ),
                        const Spacer(),
                        Text('Сейчас играет',
                            style: SeeUTypography.caption.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            )),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Скоро',
                          onPressed: null,
                          icon: Icon(PhosphorIcons.queue(),
                              color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  // Большая обложка с пульсирующим scale
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _coverPulse,
                        builder: (_, child) {
                          final t = SeeUMotion.breathe
                              .transform(_coverPulse.value);
                          // Лёгкое колебание 0.97..1.0 когда играет, иначе фиксировано 0.96
                          final scale = state.playing
                              ? 0.97 + 0.03 * t
                              : 0.96;
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
                                    placeholder: (_, __) => Container(
                                      color: Colors.white12,
                                    ),
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
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Title + artist
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
                    child: Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: SeeUTypography.displayS.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.body.copyWith(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Scrubber + времена
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: SeeUColors.accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor:
                          SeeUColors.accent.withValues(alpha: 0.18),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14),
                    ),
                    child: Slider(
                      value: shownMs.clamp(0.0, maxMs),
                      max: maxMs,
                      onChangeStart: (v) => setState(() => _scrubbing = v),
                      onChanged: (v) => setState(() => _scrubbing = v),
                      onChangeEnd: (v) async {
                        await notifier
                            .seek(Duration(milliseconds: v.round()));
                        if (mounted) setState(() => _scrubbing = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(shownDuration),
                            style: SeeUTypography.caption.copyWith(
                                color: Colors.white70, fontSize: 12)),
                        Text('-${_fmt(dur - shownDuration)}',
                            style: SeeUTypography.caption.copyWith(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Play/pause primary + close
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _IconBtn(
                        icon: PhosphorIcons.skipBack(PhosphorIconsStyle.fill),
                        onTap: null, // queue нет — отложено
                      ),
                      GestureDetector(
                        onTap: notifier.toggle,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SeeUGradients.heroOrange,
                            boxShadow: [
                              BoxShadow(
                                color: SeeUColors.accent
                                    .withValues(alpha: 0.5),
                                blurRadius: 26,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              state.playing
                                  ? PhosphorIcons.pause(
                                      PhosphorIconsStyle.fill)
                                  : PhosphorIcons.play(
                                      PhosphorIconsStyle.fill),
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      _IconBtn(
                        icon: PhosphorIcons
                            .skipForward(PhosphorIconsStyle.fill),
                        onTap: null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Close в контексте: «закрыть совсем» = stop
                  TextButton.icon(
                    onPressed: () async {
                      // Capture Navigator до async gap чтобы analyzer не ругался
                      // на use_build_context_synchronously.
                      final nav = Navigator.of(context);
                      await notifier.close();
                      if (mounted) nav.maybePop();
                    },
                    icon: Icon(PhosphorIcons.x(),
                        color: Colors.white70, size: 16),
                    label: Text(
                      'Остановить',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 28,
      icon: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white),
    );
  }
}
