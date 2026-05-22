import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Small circular control button (mute, camera, speaker).
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

/// Large circular action button (hang up, accept).
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
    return GestureDetector(
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
