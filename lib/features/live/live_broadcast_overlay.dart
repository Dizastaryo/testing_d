import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import 'live_broadcast_service.dart';

/// Fullscreen overlay shown while the user is broadcasting (LiveKit publisher).
/// Renders the local camera track + a live HUD: red LIVE badge, elapsed time,
/// viewer count, mic/flip controls, end-stream button.
class LiveBroadcastOverlay extends ConsumerStatefulWidget {
  const LiveBroadcastOverlay({super.key});

  @override
  ConsumerState<LiveBroadcastOverlay> createState() =>
      _LiveBroadcastOverlayState();
}

class _LiveBroadcastOverlayState extends ConsumerState<LiveBroadcastOverlay> {
  bool _ending = false;
  DateTime? _startedAt;
  Timer? _elapsedTimer;
  String _elapsedLabel = '0:00';

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final d = DateTime.now().difference(_startedAt!);
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      setState(() => _elapsedLabel = '$m:${s.toString().padLeft(2, '0')}');
    });
    LiveBroadcastService.instance.viewerCount.addListener(_rebuild);
    LiveBroadcastService.instance.isLive.addListener(_onLiveChanged);
  }

  void _rebuild() => setState(() {});

  void _onLiveChanged() {
    if (!LiveBroadcastService.instance.isLive.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    LiveBroadcastService.instance.viewerCount.removeListener(_rebuild);
    LiveBroadcastService.instance.isLive.removeListener(_onLiveChanged);
    super.dispose();
  }

  Future<void> _end() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      final api = ref.read(apiClientProvider);
      // endBroadcast flips isLive=false → _onLiveChanged handles the pop.
      await LiveBroadcastService.instance.endBroadcast(api);
    } catch (_) {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerCount = LiveBroadcastService.instance.viewerCount.value;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Local camera preview (LiveKit track).
          Positioned.fill(
            child: ValueListenableBuilder<LocalVideoTrack?>(
              valueListenable: LiveBroadcastService.instance.localVideoTrack,
              builder: (_, track, __) {
                if (track == null) {
                  return const ColoredBox(color: Colors.black);
                }
                return VideoTrackRenderer(
                  track,
                  fit: VideoViewFit.cover,
                  mirrorMode: VideoViewMirrorMode.auto,
                );
              },
            ),
          ),

          // Dark gradient top
          Positioned(
            top: 0, left: 0, right: 0,
            height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                ),
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Единый стеклянный статус-pill: LIVE-точка + kicker + таймер.
                _GlassPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: SeeUColors.live,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: SeeUTypography.kicker
                            .copyWith(color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _elapsedLabel,
                        style: SeeUTypography.mono.copyWith(
                          color: Colors.white,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Viewer count — стеклянный pill.
                _GlassPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsFill.eye,
                          color: Colors.white70, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        '$viewerCount',
                        style: SeeUTypography.mono.copyWith(
                          color: Colors.white,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // End stream — стеклянный pill с danger-тинтом.
                Tappable.scaled(
                  onTap: _ending ? null : _end,
                  child: AnimatedOpacity(
                    opacity: _ending ? 0.5 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: _GlassPill(
                      tint: SeeUColors.danger,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: _ending
                          ? const SizedBox(
                              width: 60,
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(PhosphorIconsRegular.x,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Завершить',
                                  style: SeeUTypography.caption.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom gradient (accounts for home indicator)
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: 120 + bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                ),
              ),
            ),
          ),

          // In-broadcast controls: mute mic + flip camera.
          Positioned(
            bottom: bottom + 28,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: LiveBroadcastService.instance.micEnabled,
                  builder: (_, micOn, __) => SeeUGlassCircleButton(
                    size: 52,
                    blur: 22,
                    // Актив — accent-стекло; выключенный мик — danger-стекло.
                    tint: micOn ? SeeUColors.accent : SeeUColors.danger,
                    icon: Icon(
                      micOn
                          ? PhosphorIconsFill.microphone
                          : PhosphorIconsFill.microphoneSlash,
                      color: Colors.white,
                      size: 22,
                    ),
                    onTap: () => LiveBroadcastService.instance.toggleMic(),
                  ),
                ),
                const SizedBox(width: 28),
                SeeUGlassCircleButton(
                  size: 52,
                  blur: 22,
                  tint: SeeUColors.accent,
                  icon: const Icon(PhosphorIconsFill.cameraRotate,
                      color: Colors.white, size: 22),
                  onTap: () => LiveBroadcastService.instance.switchCamera(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Стеклянный pill над видео (рецепт стекла: blur 22 + градиент + hairline).
/// [tint] — цветное стекло (например `SeeUColors.danger` для «Завершить»).
class _GlassPill extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;

  const _GlassPill({
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  });

  @override
  Widget build(BuildContext context) {
    final Color top = (tint ?? Colors.white).withValues(alpha: 0.14);
    final Color bottom = tint != null
        ? tint!.withValues(alpha: 0.34)
        : Colors.black.withValues(alpha: 0.28);
    final Color border =
        (tint ?? Colors.white).withValues(alpha: tint != null ? 0.45 : 0.18);

    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(color: border, width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}
