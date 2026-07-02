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
import 'camera_bottom_panel.dart' show kStoryMaxVideoSeconds;
import 'camera_ui_kit.dart';

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
  Duration? _videoDur;

  /// Chosen publish destination: 0 = История, 1 = Публикация (default).
  int _dest = 1;

  /// A video can be published as a Story only if it's within the 1-minute
  /// limit. Photos and short videos are always allowed.
  bool get _storyAllowed =>
      !_isVideo ||
      _videoDur == null ||
      _videoDur!.inSeconds <= kStoryMaxVideoSeconds;

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
          _videoDur = ctrl.value.duration;
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
                  ],
                ),
              ),
            ),
          ),

          // ── «Куда опубликовать?» sheet ─────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _DestinationSheet(
              isVideo: _isVideo,
              storyAllowed: _storyAllowed,
              selected: _dest,
              showEdit: !_isVideo && widget.onEdit != null,
              onSelect: (d) {
                if (d == 0 && !_storyAllowed) {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Для истории видео должно быть не длиннее 1 минуты'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                HapticFeedback.selectionClick();
                setState(() => _dest = d);
              },
              onNext: () {
                HapticFeedback.mediumImpact();
                if (_dest == 0) {
                  widget.onStory();
                } else {
                  widget.onPost();
                }
              },
              onEdit: () => widget.onEdit?.call(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Destination sheet ────────────────────────────────────────────────────────

class _DestinationSheet extends StatelessWidget {
  final bool isVideo;
  final bool storyAllowed;
  final int selected;
  final bool showEdit;
  final ValueChanged<int> onSelect;
  final VoidCallback onNext;
  final VoidCallback onEdit;

  const _DestinationSheet({
    required this.isVideo,
    required this.storyAllowed,
    required this.selected,
    required this.showEdit,
    required this.onSelect,
    required this.onNext,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SeeUColors.cameraDarkOverlay,
        borderRadius: BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text('Куда опубликовать?',
                  style: SeeUTypography.displayS.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text('ВЫБЕРИТЕ ФОРМАТ',
                  style: SeeUTypography.monoLabel
                      .copyWith(color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _DestCard(
                      icon: PhosphorIconsRegular.circleDashed,
                      title: 'История',
                      subtitle: storyAllowed ? '24 часа · 9:16' : 'видео до 1 мин',
                      selected: selected == 0,
                      enabled: storyAllowed,
                      onTap: () => onSelect(0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DestCard(
                      icon: PhosphorIconsFill.squaresFour,
                      title: isVideo ? 'Рилс' : 'Публикация',
                      subtitle: 'В ленту · навсегда',
                      selected: selected == 1,
                      enabled: true,
                      onTap: () => onSelect(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Далее
              GestureDetector(
                onTap: onNext,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                    boxShadow: [
                      BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Далее',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700)),
                      SizedBox(width: 8),
                      Icon(PhosphorIconsBold.arrowRight,
                          color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),

              if (showEdit) ...[
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: onEdit,
                    child: Text('Редактировать кадр',
                        style: SeeUTypography.caption
                            .copyWith(color: Colors.white70)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = SeeUColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: AnimatedContainer(
          duration: SeeUMotion.normal,
          curve: SeeUMotion.smooth,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.10),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: Icon(icon,
                        color: selected ? accent : Colors.white70, size: 20),
                  ),
                  const Spacer(),
                  // Selected check badge
                  AnimatedScale(
                    scale: selected ? 1.0 : 0.0,
                    duration: SeeUMotion.quick,
                    curve: SeeUMotion.overshoot,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: const Icon(PhosphorIconsBold.check,
                          color: Colors.white, size: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
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
      return const Center(child: BrandedLoader());
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
          // #50: play affordance scales/fades in when paused.
          Align(
            alignment: const Alignment(0, -0.35),
            child: AnimatedScale(
              scale: isPlaying ? 0.7 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 1),
                  ),
                  child: const Icon(PhosphorIconsFill.play,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
          // Progress bar with a thumb (#49) — kept above the destination sheet.
          Positioned(
            bottom: 410,
            left: 20,
            right: 20,
            child: ValueListenableBuilder(
              valueListenable: ctrl!,
              builder: (_, value, __) {
                final pos = value.position.inMilliseconds.toDouble();
                final dur = value.duration.inMilliseconds.toDouble();
                final pct = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                return SizedBox(
                  height: 10,
                  child: LayoutBuilder(
                    builder: (context, cns) => Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          height: 3,
                          width: pct * cns.maxWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Positioned(
                          left: (pct * cns.maxWidth - 5).clamp(0.0, cns.maxWidth - 10),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

