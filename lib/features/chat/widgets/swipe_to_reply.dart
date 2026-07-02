import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/tokens.dart';

/// Wraps a message bubble. Swipe right → triggers [onReply].
/// Shows a reply arrow icon that fades in as the user drags.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const SwipeToReply({super.key, required this.child, required this.onReply});

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  double _dragX = 0;
  bool _triggered = false;
  bool _dragStarted = false; // #31: haptic при начале свайпа
  static const _threshold = 64.0;

  void _onUpdate(DragUpdateDetails d) {
    // Only allow rightward drag
    final next = (_dragX + d.delta.dx).clamp(0.0, _threshold * 1.3);
    setState(() => _dragX = next);
    // #31: лёгкий haptic как только пользователь начал тянуть вправо
    if (!_dragStarted && _dragX > 0) {
      _dragStarted = true;
      HapticFeedback.selectionClick();
    }
    if (!_triggered && _dragX >= _threshold) {
      _triggered = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (_triggered) widget.onReply();
    setState(() {
      _dragX = 0;
      _triggered = false;
      _dragStarted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragX / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() {
        _dragX = 0;
        _triggered = false;
        _dragStarted = false;
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply icon behind the bubble
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + progress * 0.5,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.arrowBendUpLeft(),
                      size: 16,
                      color: SeeUColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The message itself, sliding right
          AnimatedContainer(
            duration: _dragX == 0
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dragX, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
