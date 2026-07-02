import 'package:flutter/material.dart';

/// Wraps [child] in a vertical-drag gesture that pops the current route
/// when the user drags down (or up) past [threshold] pixels.
///
/// While dragging, the child translates vertically and fades out, giving
/// a smooth dismiss feel similar to Instagram stories / TikTok close.
///
/// Usage:
/// ```dart
/// SwipeToDismiss(child: MyFullScreenContent())
/// ```
class SwipeToDismiss extends StatefulWidget {
  final Widget child;

  /// Minimum vertical drag distance (in px) to trigger dismiss.
  final double threshold;

  /// If true, only downward drags dismiss. If false, both directions work.
  final bool downOnly;

  /// Optional callback instead of default `Navigator.pop`.
  final VoidCallback? onDismiss;

  const SwipeToDismiss({
    super.key,
    required this.child,
    this.threshold = 80,
    this.downOnly = false,
    this.onDismiss,
  });

  @override
  State<SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<SwipeToDismiss> {
  double _dragOffset = 0;
  bool _dragging = false;

  void _onDragUpdate(DragUpdateDetails d) {
    final dy = _dragOffset + d.delta.dy;
    if (widget.downOnly && dy < 0) return;
    setState(() {
      _dragging = true;
      _dragOffset = dy;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset.abs() > widget.threshold) {
      if (widget.onDismiss != null) {
        widget.onDismiss!();
      } else {
        Navigator.of(context).maybePop();
      }
    }
    setState(() {
      _dragOffset = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset.abs() / (widget.threshold * 2)).clamp(0.0, 1.0);
    final opacity = 1.0 - progress * 0.5;
    final scale = 1.0 - progress * 0.05;

    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: AnimatedOpacity(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
        opacity: opacity,
        child: AnimatedScale(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
          scale: scale,
          child: AnimatedSlide(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            offset: Offset(0, _dragOffset / MediaQuery.of(context).size.height),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
