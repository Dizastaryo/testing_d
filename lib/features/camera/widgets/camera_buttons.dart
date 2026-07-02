import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

// ─── Shared glass constants ───────────────────────────────────────────────────
// All camera buttons pull from one source so the system stays consistent.

const double _kButtonBlur = 18.0;
const double _kButtonTint = 0.28;
const double _kButtonBorder = 0.18;
const double _kButtonHighlight = 0.14; // top-inner white highlight

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
  final String? tooltip;

  const CameraToolButton({
    super.key,
    required this.icon,
    this.active = false,
    this.onTap,
    this.badge,
    this.disabled = false,
    this.tooltip,
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
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.84).animate(
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
    final button = GestureDetector(
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
              ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: _kButtonBlur, sigmaY: _kButtonBlur),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: widget.active
                          ? null
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: widget.disabled ? 0.04 : _kButtonHighlight),
                                Colors.black.withValues(alpha: widget.disabled ? 0.12 : _kButtonTint),
                              ],
                            ),
                      color: widget.active ? Colors.white : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.active
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: widget.disabled ? 0.06 : _kButtonBorder),
                        width: 0.8,
                      ),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: widget.disabled ? 0.35 : 1.0,
                        child: widget.icon,
                      ),
                    ),
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

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  const _BadgePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: SeeUColors.accent,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.50),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

// ─── CameraGlassButton ─────────────────────────────────────────────────────

/// Круглая прозрачная кнопка для верхней панели (закрыть, перевернуть камеру).
/// Premium glassmorphism: backdrop blur + top inner highlight + scale press.
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
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
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
      onTapDown: (_) {
        setState(() => _pressed = true);
        _tapCtrl.forward();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _tapCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _tapCtrl.reverse();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _tapCtrl,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.10 * _tapCtrl.value,
          child: child,
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: _kButtonBlur, sigmaY: _kButtonBlur),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _pressed
                      ? [
                          Colors.white.withValues(alpha: 0.06),
                          Colors.black.withValues(alpha: 0.38),
                        ]
                      : [
                          Colors.white.withValues(alpha: _kButtonHighlight),
                          Colors.black.withValues(alpha: _kButtonTint),
                        ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: _kButtonBorder),
                  width: 0.8,
                ),
              ),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CameraNestedButton ────────────────────────────────────────────────────

/// Круглая кнопка для элементов ВНУТРИ уже заблюренной стеклянной рамки
/// (верхняя/нижняя панель). В отличие от [CameraGlassButton], НЕ имеет своего
/// `BackdropFilter` — иначе получилось бы «стекло на стекле» (двойной блюр +
/// рассинхрон тинта). Вместо этого — плоский вложенный тинт (white 10% + бордюр),
/// единый язык с музыка-чипом, undo и «эффектами».
class CameraNestedButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const CameraNestedButton({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<CameraNestedButton> createState() => _CameraNestedButtonState();
}

class _CameraNestedButtonState extends State<CameraNestedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
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
      onTapDown: (_) => _tapCtrl.forward(),
      onTapUp: (_) {
        _tapCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tapCtrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _tapCtrl,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.10 * _tapCtrl.value,
          child: child,
        ),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
