import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/tokens.dart';

/// Shared, consistent loading / empty / error primitives used across the
/// camera → publish flow. Centralizing them fixes the audit items about
/// inconsistent loaders (#95) and bare text empty/error states (#96).

/// A single branded loader. [onDark] picks light-on-dark vs accent-on-light.
class BrandedLoader extends StatelessWidget {
  final String? label;
  final bool onDark;
  final double size;

  const BrandedLoader({
    super.key,
    this.label,
    this.onDark = true,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : SeeUColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 14),
          Text(
            label!,
            style: TextStyle(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : SeeUColors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// Consistent empty / error state: icon + message + optional action.
class StatusView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool onDark;

  const StatusView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : SeeUColors.textPrimary;
    final sub = onDark ? Colors.white.withValues(alpha: 0.55) : SeeUColors.textTertiary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: sub, size: 44),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 14),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsRegular.arrowClockwise,
                          color: SeeUColors.accent, size: 16),
                      const SizedBox(width: 7),
                      Text(
                        actionLabel!,
                        style: const TextStyle(
                          color: SeeUColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
