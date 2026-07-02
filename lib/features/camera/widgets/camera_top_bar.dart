import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import '../../post/widgets/music_picker_sheet.dart' show AudioTrack;
import 'camera_buttons.dart';
import 'camera_painters.dart';

// Unified glass constants (keep in sync with camera_buttons.dart)
const double _kPanelBlur = 28.0;
const double _kPanelBorder = 0.09; // 9% white border

/// Верхняя панель камеры:
/// [X] (закрыть) · «Добавить музыку» / трек · [↺] (перевернуть)
class CameraTopBar extends StatelessWidget {
  final AudioTrack? selectedTrack;
  final Animation<double> switchRotationAnim;
  final bool canSwitchCamera;
  final bool showSwitchCamera;
  final VoidCallback onMusicTap;
  final VoidCallback onSwitchCamera;
  final VoidCallback? onClearTrack;

  const CameraTopBar({
    super.key,
    required this.selectedTrack,
    required this.switchRotationAnim,
    required this.canSwitchCamera,
    this.showSwitchCamera = true,
    required this.onMusicTap,
    required this.onSwitchCamera,
    this.onClearTrack,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: _kPanelBlur, sigmaY: _kPanelBlur),
          child: Container(
            decoration: BoxDecoration(
              // Glassmorphism: стеклянная панель — backdrop-blur (выше по дереву)
              // + мягкий градиент (светлый блик сверху → тёмный тинт снизу) +
              // светлый бордюр. Единый стиль с кнопками и полосами пикеров.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.30),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: _kPanelBorder),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 44),

                    Expanded(
                      child: Center(
                        child: _MusicChip(
                          selectedTrack: selectedTrack,
                          onTap: onMusicTap,
                          onClear: onClearTrack,
                        ),
                      ),
                    ),

                    // Flip camera — hidden when AR mask active.
                    if (showSwitchCamera)
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
                        child: CameraNestedButton(
                          onTap: canSwitchCamera ? onSwitchCamera : () {},
                          child: const Icon(PhosphorIconsRegular.arrowsClockwise,
                              color: Colors.white, size: 19),
                        ),
                      )
                    else
                      const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

// ── Music chip ────────────────────────────────────────────────────────────────

class _MusicChip extends StatelessWidget {
  final AudioTrack? selectedTrack;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _MusicChip({
    required this.selectedTrack,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = selectedTrack != null;
    const kAccent = SeeUColors.accent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SeeUMotion.slow,
        curve: SeeUMotion.smooth,
        constraints: BoxConstraints(maxWidth: hasTrack ? 230 : 200),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          // Chip sits inside the already-blurred top bar — use a light tint
          // so it reads as a nested glass layer without looking like a solid block.
          color: hasTrack
              ? kAccent.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: hasTrack
                ? kAccent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasTrack
                  ? PhosphorIconsFill.musicNotes
                  : PhosphorIconsRegular.musicNotes,
              color: hasTrack ? kAccent : Colors.white,
              size: 15,
            ),
            const SizedBox(width: 7),
            if (hasTrack) ...[
              const CameraWaveform(),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  selectedTrack!.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Icon(PhosphorIconsBold.x,
                    color: Colors.white.withValues(alpha: 0.65), size: 12),
              ),
            ] else
              Text(
                'Добавить музыку',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.90),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
