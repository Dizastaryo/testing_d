import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../core/design/tokens.dart';
import '../../post/widgets/music_picker_sheet.dart' show AudioTrack;
import 'camera_buttons.dart';

/// Полноэкранный оверлей превью медиа после съёмки/выбора из галереи.
///
/// Показывает:
/// - Фото (InteractiveViewer) или видео (с play/pause + прогресс-баром)
/// - Верхний бар: [←] [музыкальный pill] [Изменить]
/// - Нижний бар: [ИСТОРИЯ] [ПУБЛИКАЦИЯ]
class CameraGalleryPreview extends StatefulWidget {
  final XFile file;
  final Uint8List? bytes;
  final AudioTrack? selectedTrack;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;
  final VoidCallback onClose;
  final VoidCallback onStory;
  final VoidCallback onPost;
  final Future<void> Function()? onEdit; // only for photos

  const CameraGalleryPreview({
    super.key,
    required this.file,
    required this.bytes,
    required this.selectedTrack,
    required this.fadeAnim,
    required this.slideAnim,
    required this.onClose,
    required this.onStory,
    required this.onPost,
    this.onEdit,
  });

  @override
  State<CameraGalleryPreview> createState() => _CameraGalleryPreviewState();
}

class _CameraGalleryPreviewState extends State<CameraGalleryPreview> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _videoPlaying = false;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  bool get _isVideo {
    final ext = widget.file.path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext);
  }

  Future<void> _initVideo() async {
    try {
      final ctrl = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(widget.file.path))
          : VideoPlayerController.file(File(widget.file.path));
      _videoCtrl = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) {
        setState(() {
          _videoReady = true;
          _videoPlaying = true;
        });
      }
    } catch (e) {
      debugPrint('CameraGalleryPreview video init: $e');
    }
  }

  void _toggleVideoPlayback() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !_videoReady) return;
    HapticFeedback.selectionClick();
    if (_videoPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() => _videoPlaying = !_videoPlaying);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: widget.fadeAnim,
        child: SlideTransition(
          position: widget.slideAnim,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Media ──────────────────────────────────────────────────────
          if (_isVideo)
            _VideoPreview(
              ctrl: _videoCtrl,
              isReady: _videoReady,
              isPlaying: _videoPlaying,
              onTogglePlay: _toggleVideoPlayback,
            )
          else
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: widget.bytes != null
                  ? Image.memory(widget.bytes!, fit: BoxFit.contain)
                  : Container(color: Colors.black),
            ),

          // ── Top gradient ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 130,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [SeeUColors.darkScrim, SeeUColors.transparentBlack],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom gradient ────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0, height: 220,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, SeeUColors.transparentBlack],
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar ────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Back
                    CameraGlassButton(
                      onTap: widget.onClose,
                      child: const Icon(PhosphorIconsRegular.arrowLeft,
                          color: Colors.white, size: 20),
                    ),
                    const Spacer(),

                    // Music pill
                    if (widget.selectedTrack != null)
                      _MusicPill(track: widget.selectedTrack!),

                    if (widget.selectedTrack != null)
                      const SizedBox(width: 8),

                    // Edit button (photos only)
                    if (!_isVideo && widget.onEdit != null)
                      CameraGlassButton(
                        onTap: () => widget.onEdit?.call(),
                        child: const Icon(PhosphorIconsRegular.pencilSimple,
                            color: Colors.white, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom publish row ─────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Row(
                  children: [
                    // История
                    Expanded(
                      child: _PublishButton(
                        label: 'История',
                        isAccent: false,
                        onTap: widget.onStory,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Публикация
                    Expanded(
                      child: _PublishButton(
                        label: 'Публикация',
                        isAccent: true,
                        onTap: widget.onPost,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Video preview ────────────────────────────────────────────────────────────

class _VideoPreview extends StatelessWidget {
  final VideoPlayerController? ctrl;
  final bool isReady;
  final bool isPlaying;
  final VoidCallback onTogglePlay;

  const _VideoPreview({
    required this.ctrl,
    required this.isReady,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    if (ctrl == null || !isReady) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
      );
    }
    return GestureDetector(
      onTap: onTogglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: ctrl!.value.size.width,
              height: ctrl!.value.size.height,
              child: VideoPlayer(ctrl!),
            ),
          ),
          if (!isPlaying)
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.50),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 1),
                ),
                child: const Icon(PhosphorIconsFill.play,
                    color: Colors.white, size: 24),
              ),
            ),
          // Progress bar
          Positioned(
            bottom: 130,
            left: 20,
            right: 20,
            child: ValueListenableBuilder(
              valueListenable: ctrl!,
              builder: (_, value, __) {
                final pos = value.position.inMilliseconds.toDouble();
                final dur = value.duration.inMilliseconds.toDouble();
                final pct = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 2,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Music pill ───────────────────────────────────────────────────────────────

class _MusicPill extends StatelessWidget {
  final AudioTrack track;
  const _MusicPill({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(
          color: SeeUColors.accent.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsFill.musicNote,
              color: SeeUColors.accent, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              track.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Publish button ───────────────────────────────────────────────────────────

class _PublishButton extends StatelessWidget {
  final String label;
  final bool isAccent;
  final VoidCallback onTap;

  const _PublishButton({
    required this.label,
    required this.isAccent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: isAccent
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                )
              : null,
          color: isAccent ? null : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: isAccent
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
          boxShadow: isAccent
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
