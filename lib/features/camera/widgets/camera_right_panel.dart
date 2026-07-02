import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';

/// Правая вертикальная колонка инструментов камеры.
/// Нажатие на стрелку сворачивает/разворачивает панель с анимацией.
class CameraRightPanel extends StatefulWidget {
  final bool isFrontCamera;
  final int flashMode; // 0=off, 1=torch, 2=auto
  final int timerSetting; // 0 / 3 / 10
  final bool showGrid;
  final bool maskPickerActive;
  final bool handsFreeActive;
  final bool isLive;
  final Animation<double> flashPulseAnim;

  final VoidCallback onToggleFlash;
  final VoidCallback onToggleTimer;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleMaskPicker;
  final VoidCallback onToggleHandsFree;
  final VoidCallback onToggleLive;

  const CameraRightPanel({
    super.key,
    required this.isFrontCamera,
    required this.flashMode,
    required this.timerSetting,
    required this.showGrid,
    this.maskPickerActive = false,
    this.handsFreeActive = false,
    this.isLive = false,
    required this.flashPulseAnim,
    required this.onToggleFlash,
    required this.onToggleTimer,
    required this.onToggleGrid,
    required this.onToggleMaskPicker,
    required this.onToggleHandsFree,
    required this.onToggleLive,
  });

  @override
  State<CameraRightPanel> createState() => _CameraRightPanelState();
}

class _CameraRightPanelState extends State<CameraRightPanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _arrowCtrl;
  late final Animation<double> _arrowTurn;

  @override
  void initState() {
    super.initState();
    // 0 = expanded (arrow → pointing right = "close")
    // 0.5 = collapsed (arrow → rotated 180° = pointing left = "open")
    _arrowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _arrowTurn = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _arrowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _arrowCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _arrowCtrl.reverse();
    } else {
      _arrowCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Flash icon logic
    final IconData flashIcon;
    final bool flashActive;
    final String? flashBadge;
    if (widget.isFrontCamera) {
      flashIcon = PhosphorIconsRegular.lightningSlash;
      flashActive = false;
      flashBadge = null;
    } else if (widget.flashMode == 1) {
      flashIcon = PhosphorIconsFill.lightning;
      flashActive = true;
      flashBadge = null;
    } else if (widget.flashMode == 2) {
      flashIcon = PhosphorIconsFill.lightning;
      flashActive = true;
      flashBadge = 'A';
    } else {
      flashIcon = PhosphorIconsRegular.lightning;
      flashActive = false;
      flashBadge = null;
    }

    return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.black.withValues(alpha: 0.22),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.6,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Toggle arrow — always visible. Rotates 180° when collapsed.
                GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 42,
                    height: 32,
                    child: Center(
                      child: RotationTransition(
                        turns: _arrowTurn,
                        child: Icon(
                          PhosphorIconsRegular.caretRight,
                          color: Colors.white.withValues(alpha: 0.70),
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                // Collapsible tool buttons
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _expanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Divider between arrow and tools
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              height: 0.5,
                              width: 24,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),

                            // LIVE
                            _RailButton(
                              icon: widget.isLive
                                  ? PhosphorIconsFill.broadcast
                                  : PhosphorIconsRegular.broadcast,
                              color: widget.isLive ? SeeUColors.accent : Colors.white,
                              accentRing: widget.isLive,
                              badge: widget.isLive ? 'LIVE' : null,
                              tooltip: 'Прямой эфир',
                              onTap: widget.onToggleLive,
                            ),
                            const SizedBox(height: 2),

                            // Flash
                            AnimatedBuilder(
                              animation: widget.flashPulseAnim,
                              builder: (_, child) => Transform.scale(
                                scale: 1.0 +
                                    0.15 *
                                        Curves.easeOut.transform(
                                            widget.flashPulseAnim.value),
                                child: child,
                              ),
                              child: _RailButton(
                                icon: flashIcon,
                                color: flashActive ? SeeUColors.amber : Colors.white,
                                badge: flashBadge,
                                disabled: widget.isFrontCamera,
                                tooltip: 'Вспышка',
                                onTap: widget.isFrontCamera ? null : widget.onToggleFlash,
                              ),
                            ),
                            const SizedBox(height: 2),

                            // Masks
                            _RailButton(
                              icon: widget.maskPickerActive
                                  ? PhosphorIconsFill.maskHappy
                                  : PhosphorIconsRegular.maskHappy,
                              color: widget.maskPickerActive
                                  ? SeeUColors.accentSecondary
                                  : Colors.white,
                              accentRing: widget.maskPickerActive,
                              tooltip: 'Маски',
                              onTap: widget.onToggleMaskPicker,
                            ),
                            const SizedBox(height: 2),

                            // Hands-free
                            _RailButton(
                              icon: widget.handsFreeActive
                                  ? PhosphorIconsFill.handWaving
                                  : PhosphorIconsRegular.handWaving,
                              color: widget.handsFreeActive
                                  ? SeeUColors.amber
                                  : Colors.white,
                              badge: widget.handsFreeActive ? 'ON' : null,
                              tooltip: 'Без рук',
                              onTap: widget.onToggleHandsFree,
                            ),
                            const SizedBox(height: 2),

                            // Timer
                            _RailButton(
                              icon: widget.timerSetting > 0
                                  ? PhosphorIconsFill.timer
                                  : PhosphorIconsRegular.timer,
                              color: widget.timerSetting > 0
                                  ? SeeUColors.amber
                                  : Colors.white,
                              badge: widget.timerSetting > 0
                                  ? '${widget.timerSetting}с'
                                  : null,
                              tooltip: 'Таймер',
                              onTap: widget.onToggleTimer,
                            ),
                            const SizedBox(height: 2),

                            // Grid
                            _RailButton(
                              icon: widget.showGrid
                                  ? PhosphorIconsFill.gridFour
                                  : PhosphorIconsRegular.gridFour,
                              color: widget.showGrid ? SeeUColors.amber : Colors.white,
                              tooltip: 'Сетка',
                              onTap: widget.onToggleGrid,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

// ── Rail button ──────────────────────────────────────────────────────────────

class _RailButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool accentRing;
  final bool disabled;
  final String? badge;
  final String? tooltip;
  final VoidCallback? onTap;

  const _RailButton({
    required this.icon,
    required this.color,
    this.accentRing = false,
    this.disabled = false,
    this.badge,
    this.tooltip,
    this.onTap,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  void _handle() {
    if (widget.disabled || widget.onTap == null) return;
    _tap.forward().then((_) => _tap.reverse());
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: _handle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 - 0.14 * _tap.value, child: child),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.accentRing)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeeUColors.accent.withValues(alpha: 0.20),
                    border: Border.all(
                      color: SeeUColors.accentSecondary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
              Opacity(
                opacity: widget.disabled ? 0.35 : 1.0,
                child: Icon(widget.icon, color: widget.color, size: 22),
              ),
              if (widget.badge != null)
                Positioned(
                  top: 2,
                  right: 0,
                  child: _Badge(text: widget.badge!),
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

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

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
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
