import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_button.dart';
import 'seeu_theme_colors.dart';
import 'tokens.dart';

/// Common empty/error states for screens — Feed/Explore/Profile/Notifications/etc.
///
/// Before this dedup each surface rolled its own `_buildEmpty`/`_buildError`
/// (see audit P1 — "10+ places"). Layout was the same in every place but
/// drifted: different icon sizes, different subtitle colors, missing CTAs
/// in half the screens. Two canonical widgets fix that:
///
///   SeeUEmptyState — when the list is legitimately empty (no follows yet,
///   no notifications, no music tracks).
///
///   SeeUErrorState — when fetching failed (network, server 5xx). Always
///   pairs with an onRetry callback so the user has a way out.

/// Optional CTA shown under the message (Feed empty → "Найти людей",
/// Notifications error → "Повторить", etc.).
class SeeUStateAction {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const SeeUStateAction({
    required this.label,
    required this.onTap,
    this.icon,
  });
}

class SeeUEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final SeeUStateAction? action;
  final double iconSize;

  const SeeUEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: iconSize, color: c.line),
            const SizedBox(height: 16),
            Text(
              title,
              style: SeeUTypography.subtitle.copyWith(color: c.ink2),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: SeeUTypography.caption.copyWith(color: c.ink3),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              SeeUButton(
                label: action!.label,
                onTap: action!.onTap,
                icon: action!.icon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SeeUErrorState extends StatelessWidget {
  /// Optional raw error text shown in caption-grey under the title. Truncated
  /// to 2 lines to avoid push-down of the retry button on a long stack trace.
  final String? error;
  final String title;
  final VoidCallback? onRetry;
  final IconData icon;

  const SeeUErrorState({
    super.key,
    this.error,
    this.title = 'Не удалось загрузить',
    this.onRetry,
    IconData? icon,
  }) : icon = icon ?? PhosphorIconsRegular.wifiSlash;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 56, color: c.ink3),
            const SizedBox(height: 16),
            Text(
              title,
              style: SeeUTypography.subtitle.copyWith(color: c.ink2),
              textAlign: TextAlign.center,
            ),
            if (error != null && error!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: SeeUTypography.caption.copyWith(color: c.ink3),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SeeUButton(
                label: 'Повторить',
                onTap: onRetry!,
                icon: PhosphorIconsRegular.arrowCounterClockwise,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
