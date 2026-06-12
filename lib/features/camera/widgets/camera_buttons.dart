import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

// ─── CameraToolButton ──────────────────────────────────────────────────────

/// Круглая кнопка инструмента камеры (вспышка, таймер, сетка, скорость...).
///
/// - 44×44 circle, стеклянный фон.
/// - [active] → белый фон, тёмная иконка.
/// - [badge] → оранжевый pill в правом верхнем углу ("3", "10", "2x").
/// - [disabled] → 35% opacity, tap игнорируется.
class CameraToolButton extends StatefulWidget {
  final Widget icon;
  final bool active;
  final VoidCallback? onTap;
  final String? badge;
  final bool disabled;

  const CameraToolButton({
    super.key,
    required this.icon,
    this.active = false,
    this.onTap,
    this.badge,
    this.disabled = false,
  });

  @override
  State<CameraToolButton> createState() => _CameraToolButtonState();
}

class _CameraToolButtonState extends State<CameraToolButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.86).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.disabled || widget.onTap == null) return;
    _tapCtrl.forward().then((_) => _tapCtrl.reverse());
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(scale: _scaleAnim.value, child: child),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.active
                      ? Colors.white
                      : Colors.black.withValues(alpha: widget.disabled ? 0.15 : 0.38),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.active
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: widget.disabled ? 0.08 : 0.22),
                    width: 0.8,
                  ),
                  boxShadow: widget.active
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.25),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Opacity(
                    opacity: widget.disabled ? 0.35 : 1.0,
                    child: widget.icon,
                  ),
                ),
              ),
              if (widget.badge != null)
                Positioned(
                  top: -3,
                  right: -3,
                  child: _BadgePill(text: widget.badge!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  const _BadgePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: SeeUColors.accent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

// ─── CameraGlassButton ─────────────────────────────────────────────────────

/// Круглая прозрачная кнопка для верхней панели (закрыть, перевернуть камеру).
class CameraGlassButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const CameraGlassButton({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<CameraGlassButton> createState() => _CameraGlassButtonState();
}

class _CameraGlassButtonState extends State<CameraGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _tapCtrl.forward().then((_) => _tapCtrl.reverse());
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _tapCtrl,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.12 * _tapCtrl.value,
          child: child,
        ),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 0.8,
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
