import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';

/// Small circular control button (mute, camera, speaker) — стеклянный круг
/// поверх видео. Активное состояние — accent-тинт стекла.
class CallSmallButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const CallSmallButton({
    super.key,
    required this.icon,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SeeUGlassCircleButton(
      size: 54,
      blur: 22,
      tint: active ? SeeUColors.accent : null,
      icon: Icon(icon, color: Colors.white, size: 24),
      // Haptic — внутри Tappable.scaled (SeeUGlassCircleButton).
      onTap: onTap,
    );
  }
}

/// Large circular action button (hang up, accept) — solid, с press-scale.
class CallBigButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const CallBigButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      enableHaptic: false,
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }
}
