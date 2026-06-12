import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tokens.dart';

/// Универсальная кнопка лайка — heart icon + счётчик (опционально).
/// Поддерживает optimistic updates: вызывает [onToggle] и немедленно
/// меняет UI, откатывает при ошибке.
///
/// Пример:
/// ```dart
/// SeeULikeButton(
///   isLiked: track.isLiked,
///   count: track.likesCount,
///   onToggle: (newState) async => await likeTrack(track.id),
/// )
/// ```
class SeeULikeButton extends StatefulWidget {
  final bool isLiked;
  final int? count;
  final Future<void> Function(bool newLikedState) onToggle;
  final double iconSize;
  final bool showCount;

  const SeeULikeButton({
    super.key,
    required this.isLiked,
    required this.onToggle,
    this.count,
    this.iconSize = 22,
    this.showCount = true,
  });

  @override
  State<SeeULikeButton> createState() => _SeeULikeButtonState();
}

class _SeeULikeButtonState extends State<SeeULikeButton>
    with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late int _count;
  bool _busy = false;

  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _count = widget.count ?? 0;
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scaleAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(SeeULikeButton old) {
    super.didUpdateWidget(old);
    if (!_busy) {
      _isLiked = widget.isLiked;
      _count = widget.count ?? 0;
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    final prevLiked = _isLiked;
    final prevCount = _count;
    setState(() {
      _busy = true;
      _isLiked = !_isLiked;
      _count = _isLiked ? _count + 1 : (_count - 1).clamp(0, 999999);
    });
    _scaleCtrl.forward(from: 0);
    try {
      await widget.onToggle(_isLiked);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
          _count = prevCount;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnim,
              child: Icon(
                _isLiked
                    ? PhosphorIconsFill.heart
                    : PhosphorIconsRegular.heart,
                color: _isLiked ? SeeUColors.accent : null,
                size: widget.iconSize,
              ),
            ),
            if (widget.showCount && _count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$_count',
                style: TextStyle(
                  fontSize: widget.iconSize * 0.6,
                  fontWeight: FontWeight.w600,
                  color: _isLiked ? SeeUColors.accent : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
