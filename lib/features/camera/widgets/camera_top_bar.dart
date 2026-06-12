import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import '../../post/widgets/music_picker_sheet.dart' show AudioTrack;
import 'camera_buttons.dart';
import 'camera_painters.dart';

/// Верхняя панель камеры:
/// - Тонкий progress-бар сегментов
/// - [X] (закрыть) + Music chip + [↺] (перевернуть)
class CameraTopBar extends StatelessWidget {
  final List<double> segments;
  final double currentSegDur;
  final double maxDuration;
  final bool isRecording;
  final AudioTrack? selectedTrack;
  final Animation<double> segmentFlashAnim;
  final Animation<double> switchRotationAnim;
  final bool canSwitchCamera;
  final VoidCallback onClose;
  final VoidCallback onMusicTap;
  final VoidCallback onSwitchCamera;
  final VoidCallback? onClearTrack;

  const CameraTopBar({
    super.key,
    required this.segments,
    required this.currentSegDur,
    required this.maxDuration,
    required this.isRecording,
    required this.selectedTrack,
    required this.segmentFlashAnim,
    required this.switchRotationAnim,
    required this.canSwitchCamera,
    required this.onClose,
    required this.onMusicTap,
    required this.onSwitchCamera,
    this.onClearTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SegmentBar(
                segments: segments,
                currentSegDur: currentSegDur,
                maxDuration: maxDuration,
                isRecording: isRecording,
                flashAnim: segmentFlashAnim,
              ),
              const SizedBox(height: 12),
              _TopRow(
                selectedTrack: selectedTrack,
                switchRotationAnim: switchRotationAnim,
                canSwitchCamera: canSwitchCamera,
                onClose: onClose,
                onMusicTap: onMusicTap,
                onSwitchCamera: onSwitchCamera,
                onClearTrack: onClearTrack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segment bar ────────────────────────────────────────────────────────────

class _SegmentBar extends StatelessWidget {
  final List<double> segments;
  final double currentSegDur;
  final double maxDuration;
  final bool isRecording;
  final Animation<double> flashAnim;

  const _SegmentBar({
    required this.segments,
    required this.currentSegDur,
    required this.maxDuration,
    required this.isRecording,
    required this.flashAnim,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: AnimatedBuilder(
        animation: flashAnim,
        builder: (_, __) => CustomPaint(
          painter: CameraSegmentBarPainter(
            segments: segments,
            currentSegDur: currentSegDur,
            maxDuration: maxDuration,
            isRecording: isRecording,
            accentColor: SeeUColors.accent,
            lastSegmentFlash: flashAnim.value,
          ),
        ),
      ),
    );
  }
}

// ── Top row ─────────────────────────────────────────────────────────────────

class _TopRow extends StatelessWidget {
  final AudioTrack? selectedTrack;
  final Animation<double> switchRotationAnim;
  final bool canSwitchCamera;
  final VoidCallback onClose;
  final VoidCallback onMusicTap;
  final VoidCallback onSwitchCamera;
  final VoidCallback? onClearTrack;

  const _TopRow({
    required this.selectedTrack,
    required this.switchRotationAnim,
    required this.canSwitchCamera,
    required this.onClose,
    required this.onMusicTap,
    required this.onSwitchCamera,
    this.onClearTrack,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = selectedTrack != null;
    const glassOverlay = SeeUColors.glassOverlay;
    const kAccent = SeeUColors.accent;

    return Row(
      children: [
        // Close
        CameraGlassButton(
          onTap: onClose,
          child: const Icon(PhosphorIconsRegular.x, color: Colors.white, size: 20),
        ),

        const Spacer(),

        // Music chip
        GestureDetector(
          onTap: onMusicTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(maxWidth: hasTrack ? 210 : 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: hasTrack
                  ? kAccent.withValues(alpha: 0.22)
                  : glassOverlay,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                color: hasTrack
                    ? kAccent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasTrack
                      ? PhosphorIconsFill.musicNote
                      : PhosphorIconsRegular.musicNote,
                  color: hasTrack ? kAccent : Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 5),
                if (hasTrack) ...[
                  const CameraWaveform(),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      selectedTrack!.title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onClearTrack,
                    child: const Icon(PhosphorIconsRegular.x,
                        color: Colors.white60, size: 11),
                  ),
                ] else
                  const Text(
                    '+ Музыка',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Flip camera (3D Y-rotation)
        AnimatedBuilder(
          animation: switchRotationAnim,
          builder: (_, child) {
            final t = switchRotationAnim.value;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(t * math.pi);
            return Transform(
              transform: matrix,
              alignment: Alignment.center,
              child: child,
            );
          },
          child: CameraGlassButton(
            onTap: canSwitchCamera ? onSwitchCamera : () {},
            child: const Icon(PhosphorIconsRegular.cameraRotate,
                color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}
