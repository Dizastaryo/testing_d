import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import 'camera_buttons.dart';

/// Правая вертикальная колонка инструментов камеры.
/// Flash / Timer / Grid / Speed (видео) / Beauty (фронт)
class CameraRightPanel extends StatelessWidget {
  final bool isFrontCamera;
  final int flashMode;        // 0=off, 1=torch, 2=auto
  final int timerSetting;     // 0 / 3 / 10
  final bool showGrid;
  final double videoSpeed;    // 0.5 / 1.0 / 2.0 / 3.0
  final bool beautyOn;
  final bool isVideoMode;
  final bool presetActive;
  final Animation<double> flashPulseAnim;

  final VoidCallback onToggleFlash;
  final VoidCallback onToggleTimer;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleSpeed;
  final VoidCallback onToggleBeauty;
  final VoidCallback onTogglePresets;

  const CameraRightPanel({
    super.key,
    required this.isFrontCamera,
    required this.flashMode,
    required this.timerSetting,
    required this.showGrid,
    required this.videoSpeed,
    required this.beautyOn,
    required this.isVideoMode,
    required this.presetActive,
    required this.flashPulseAnim,
    required this.onToggleFlash,
    required this.onToggleTimer,
    required this.onToggleGrid,
    required this.onToggleSpeed,
    required this.onToggleBeauty,
    required this.onTogglePresets,
  });

  @override
  Widget build(BuildContext context) {
    final speedNotDefault = videoSpeed != 1.0;

    // Flash icon logic
    final IconData flashIcon;
    final bool flashActive;
    final String? flashBadge;
    if (isFrontCamera) {
      flashIcon = PhosphorIconsRegular.lightningSlash;
      flashActive = false;
      flashBadge = null;
    } else if (flashMode == 1) {
      flashIcon = PhosphorIconsFill.lightning;
      flashActive = true;
      flashBadge = null;
    } else if (flashMode == 2) {
      flashIcon = PhosphorIconsRegular.lightning;
      flashActive = true;
      flashBadge = 'A';
    } else {
      flashIcon = PhosphorIconsRegular.lightning;
      flashActive = false;
      flashBadge = null;
    }

    return Positioned(
      right: 12,
      top: 110,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flash
            AnimatedBuilder(
              animation: flashPulseAnim,
              builder: (_, child) => Transform.scale(
                scale: 1.0 +
                    0.15 * Curves.easeOut.transform(flashPulseAnim.value),
                child: child,
              ),
              child: CameraToolButton(
                icon: Icon(
                  flashIcon,
                  color: flashActive ? SeeUColors.textPrimary : Colors.white,
                  size: 22,
                ),
                active: flashActive,
                disabled: isFrontCamera,
                badge: flashBadge,
                onTap: isFrontCamera ? null : onToggleFlash,
              ),
            ),
            const SizedBox(height: 12),

            // Timer
            CameraToolButton(
              icon: Icon(
                PhosphorIconsRegular.timer,
                color: timerSetting > 0 ? SeeUColors.textPrimary : Colors.white,
                size: 22,
              ),
              active: timerSetting > 0,
              badge: timerSetting > 0 ? '${timerSetting}с' : null, // ignore: unnecessary_brace_in_string_interps
              onTap: onToggleTimer,
            ),
            const SizedBox(height: 12),

            // Grid
            CameraToolButton(
              icon: Icon(
                PhosphorIconsRegular.gridFour,
                color: showGrid ? SeeUColors.textPrimary : Colors.white,
                size: 22,
              ),
              active: showGrid,
              badge: showGrid ? '✓' : null,
              onTap: onToggleGrid,
            ),

            // Speed (video modes only)
            if (isVideoMode) ...[
              const SizedBox(height: 12),
              CameraToolButton(
                icon: Text(
                  '${videoSpeed % 1 == 0 ? videoSpeed.toInt() : videoSpeed}x',
                  style: TextStyle(
                    color: speedNotDefault ? SeeUColors.textPrimary : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                active: speedNotDefault,
                onTap: onToggleSpeed,
              ),
            ],

            // Beauty (front camera only)
            if (isFrontCamera) ...[
              const SizedBox(height: 12),
              CameraToolButton(
                icon: Icon(
                  beautyOn ? PhosphorIconsFill.sparkle : PhosphorIconsRegular.sparkle,
                  color: beautyOn ? SeeUColors.textPrimary : Colors.white,
                  size: 22,
                ),
                active: beautyOn,
                badge: beautyOn ? '✓' : null,
                onTap: onToggleBeauty,
              ),
            ],

            // Presets / Effects
            const SizedBox(height: 12),
            CameraToolButton(
              icon: Icon(
                presetActive ? PhosphorIconsFill.sparkle : PhosphorIconsRegular.sparkle,
                color: presetActive ? SeeUColors.accent : Colors.white,
                size: 22,
              ),
              active: presetActive,
              badge: null,
              onTap: onTogglePresets,
            ),
          ],
        ),
      ),
    );
  }
}
