import 'package:flutter/material.dart';
import 'tokens.dart';

class SeeUChip extends StatelessWidget {
  final String label;
  final Color? bgColor;
  final Color? fgColor;
  final IconData? icon;

  const SeeUChip({
    super.key,
    required this.label,
    this.bgColor,
    this.fgColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = bgColor ?? SeeUColors.accentSoft;
    final fg = fgColor ?? SeeUColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
