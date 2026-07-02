import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Universal tap wrapper with press animations.
/// Inspired by Instagram clone's Tappable widget.
enum TappableVariant { normal, faded, scaled }

class Tappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TappableVariant variant;
  final double scaleFactor;
  final Duration duration;
  final bool enableHaptic;
  final Color? splashColor;

  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.variant = TappableVariant.scaled,
    this.scaleFactor = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.enableHaptic = true,
    this.splashColor,
  });

  /// Faded variant — opacity drops on press
  const Tappable.faded({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enableHaptic = true,
    this.splashColor,
  })  : variant = TappableVariant.faded,
        scaleFactor = 1.0,
        duration = const Duration(milliseconds: 150);

  /// Scaled variant — shrinks on press
  const Tappable.scaled({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.95,
    this.enableHaptic = true,
    this.splashColor,
  })  : variant = TappableVariant.scaled,
        duration = const Duration(milliseconds: 120);

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: Duration(milliseconds: widget.duration.inMilliseconds + 50),
    );

    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnim = Tween<double>(
      begin: 1.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  void _onTap() {
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == TappableVariant.normal) {
      return GestureDetector(
        onTap: widget.onTap != null ? _onTap : null,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap != null ? _onTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          if (widget.variant == TappableVariant.faded) {
            return Opacity(opacity: _opacityAnim.value, child: child);
          }
          return Transform.scale(scale: _scaleAnim.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
