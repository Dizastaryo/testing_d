import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/design.dart';
import '../../core/services/video_pip_service.dart';

class FullscreenVideoPlayer extends ConsumerStatefulWidget {
  final String url;
  final String videoId;
  final String title;
  final String thumbnailUrl;

  const FullscreenVideoPlayer({
    super.key,
    required this.url,
    this.videoId = '',
    this.title = '',
    this.thumbnailUrl = '',
  });

  @override
  ConsumerState<FullscreenVideoPlayer> createState() =>
      _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends ConsumerState<FullscreenVideoPlayer>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _showControls = true;
  double _dragY = 0;
  bool _dragging = false;
  bool _pausedForPip = false;
  Timer? _posUpdateTimer;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: const {'Connection': 'keep-alive'},
    );
    _controller
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
          _scheduleHideControls();
          _activatePip();
        }
      }).catchError((e) {
        debugPrint('Fullscreen video error: $e');
        if (mounted) setState(() => _hasError = true);
      });
  }

  void _activatePip() {
    // BACKGROUND AUDIO: playback-категория, чтобы звук жил при блокировке экрана.
    configureVideoBackgroundAudio();
    final vsize = _controller.value.size;
    ref.read(videoPipProvider.notifier).setActive(
          active: true,
          videoId: widget.videoId,
          url: widget.url,
          title: widget.title,
          thumbnailUrl: widget.thumbnailUrl,
          aspectWidth: vsize.width > 0 ? vsize.width.round() : 16,
          aspectHeight: vsize.height > 0 ? vsize.height.round() : 9,
        );
    // Update position every 3 s so it's current when PiP starts.
    _posUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      ref.read(videoPipProvider.notifier).updatePosition(
            _controller.value.position.inMilliseconds,
          );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    if (state == AppLifecycleState.paused && Platform.isIOS) {
      // iOS: реальный уход в фон → start native video PiP. Используем `paused`,
      // а не `inactive` (тот срабатывает на Control Center / переключатель
      // приложений / системные диалоги и давал ложный запуск PiP).
      ref.read(videoPipProvider.notifier).updatePosition(
            _controller.value.position.inMilliseconds,
          );
      // Native iOS PiP spins up its own AVPlayer; pause this controller so the
      // two don't play the same audio track simultaneously (double audio on lock).
      if (_controller.value.isPlaying) {
        _pausedForPip = true;
        _controller.pause();
      }
      ref.read(videoPipProvider.notifier).startIosPip();
    } else if (state == AppLifecycleState.paused && Platform.isAndroid) {
      // Android: уход в фон → запрос системного PiP (зеркалит iOS-путь).
      ref.read(videoPipProvider.notifier).updatePosition(
            _controller.value.position.inMilliseconds,
          );
      ref.read(videoPipProvider.notifier).startAndroidPip();
    } else if (state == AppLifecycleState.resumed && _pausedForPip) {
      // Вернулись из фона (PiP свернут) → восстанавливаем позицию, до которой
      // дошёл нативный PiP-плеер, и возобновляем встроенный плеер.
      _pausedForPip = false;
      final pipPos = ref.read(videoPipProvider).video?.positionMs ?? 0;
      if (pipPos > 0) {
        final target = Duration(milliseconds: pipPos);
        if ((target - _controller.value.position).abs() >
            const Duration(seconds: 1)) {
          _controller.seekTo(target);
        }
      }
      _controller.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    _controller.dispose();
    ref.read(videoPipProvider.notifier).setActive(active: false);
    super.dispose();
  }

  void _scheduleHideControls() {
    // Single cancellable timer — restart instead of stacking Future.delayed
    // calls that would each fire and fight over _showControls.
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTap() {
    if (!_initialized) return;

    if (_showControls) {
      // Toggle play/pause
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
        _scheduleHideControls();
      }
      setState(() {});
    } else {
      // Show controls
      setState(() => _showControls = true);
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _onTap,
          onVerticalDragUpdate: (d) {
            setState(() {
              _dragY += d.delta.dy;
              _dragging = true;
            });
          },
          onVerticalDragEnd: (d) {
            if (_dragY > 100 || d.velocity.pixelsPerSecond.dy > 500) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _dragY = 0;
                _dragging = false;
              });
            }
          },
          child: AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(0, _dragY.clamp(0, 400), 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video
                if (_initialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  )
                else if (_hasError)
                  Theme(
                    data: ThemeData(brightness: Brightness.dark),
                    child: SeeUErrorState(
                      title: 'Не удалось загрузить видео',
                      icon: PhosphorIconsRegular.warningCircle,
                    ),
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white24, strokeWidth: 2.5),
                  ),

                // Editorial title — top-left kicker + Fraunces headline.
                if (widget.title.trim().isNotEmpty && _showControls)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 64,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ВИДЕО',
                          style: SeeUTypography.kicker.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.displayS.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Center glass play/pause — reflects isPlaying.
                if (_initialized && _showControls)
                  Center(
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (_, value, __) => SeeUGlassCircleButton(
                        size: 68,
                        icon: PhosphorIcon(
                          value.isPlaying
                              ? PhosphorIconsFill.pause
                              : PhosphorIconsFill.play,
                          color: Colors.white,
                          size: 30,
                        ),
                        onTap: () {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                            _scheduleHideControls();
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ),

                // Close button — always visible
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: SeeUGlassCircleButton(
                    icon: PhosphorIcon(PhosphorIconsRegular.x,
                        color: Colors.white, size: 20),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),

                // Seek bar at bottom — shown with controls. Only this subtree
                // rebuilds per playback tick (ValueListenableBuilder), instead
                // of setState'ing the whole player tree every frame.
                if (_initialized && _showControls)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (_, value, __) => _buildSeekBar(value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar(VideoPlayerValue value) {
    final position = value.position;
    final duration = value.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final timeStyle = SeeUTypography.mono.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
    );

    // Frosted glass panel + bottom darkScrim so labels read over bright frames.
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.medium),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SeeUColors.glassOverlay, SeeUColors.darkScrim],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: timeStyle),
                  Text(_formatDuration(duration), style: timeStyle),
                ],
              ),
              const SizedBox(height: 2),
              // Slider
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: SeeUColors.accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                  thumbColor: Colors.white,
                  overlayColor: SeeUColors.accent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChangeStart: (_) => _hideControlsTimer?.cancel(),
                  onChanged: (v) {
                    final pos = Duration(
                      milliseconds: (v * duration.inMilliseconds).round(),
                    );
                    // No setState needed: the seek updates the controller value,
                    // which the wrapping ValueListenableBuilder picks up.
                    _controller.seekTo(pos);
                  },
                  onChangeEnd: (_) {
                    _scheduleHideControls();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
