import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

enum SeeUButtonVariant { primary, secondary, ghost }

class SeeUButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final SeeUButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const SeeUButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = SeeUButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 52,
  });

  @override
  State<SeeUButton> createState() => _SeeUButtonState();
}

class _SeeUButtonState extends State<SeeUButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _scaleCtrl.forward();
  void _onTapUp(TapUpDetails _) => _scaleCtrl.reverse();
  void _onTapCancel() => _scaleCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onTap == null && !widget.isLoading;

    Color bgColor;
    Color fgColor;
    List<BoxShadow>? shadow;
    Border? border;

    switch (widget.variant) {
      case SeeUButtonVariant.primary:
        bgColor = isDisabled
            ? SeeUColors.accent.withValues(alpha: 0.4)
            : SeeUColors.accent;
        fgColor = Colors.white;
        shadow = isDisabled ? null : SeeUShadows.md;
        break;
      case SeeUButtonVariant.secondary:
        bgColor = SeeUColors.surfaceElevated;
        fgColor = SeeUColors.textPrimary;
        shadow = SeeUShadows.sm;
        border = Border.all(color: SeeUColors.borderSubtle, width: 1);
        break;
      case SeeUButtonVariant.ghost:
        bgColor = Colors.transparent;
        fgColor = isDisabled ? SeeUColors.textTertiary : SeeUColors.textPrimary;
        break;
    }

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: widget.onTap != null ? _onTapDown : null,
        onTapUp: widget.onTap != null ? _onTapUp : null,
        onTapCancel: _onTapCancel,
        onTap: widget.isLoading
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap?.call();
              },
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: shadow,
            border: border,
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fgColor,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: fgColor, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: fgColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
