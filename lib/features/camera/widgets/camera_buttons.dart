import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

/// Right-side tool button (flash, grid, timer, etc).
class CameraToolButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const CameraToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? Colors.white : SeeUColors.lightScrim,
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: SeeUColors.softScrim,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular translucent button for top bar actions.
class CameraGlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const CameraGlassButton({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
