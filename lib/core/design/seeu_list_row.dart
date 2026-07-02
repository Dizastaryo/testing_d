import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'seeu_theme_colors.dart';
import 'tappable.dart';
import 'tokens.dart';

/// Аватар с опциональной online-точкой. Единый компонент вместо локальных
/// реализаций в списках пользователей/участников/чатов.
class SeeUOnlineAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final double size;
  final bool isOnline;

  /// Индекс для детерминированного градиента-фолбэка из `avatarPalettes`.
  final int paletteSeed;

  const SeeUOnlineAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackText,
    this.size = SeeUAvatarSizes.lg,
    this.isOnline = false,
    this.paletteSeed = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final palette = SeeUColors
        .avatarPalettes[paletteSeed.abs() % SeeUColors.avatarPalettes.length];

    final Widget fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
        style: SeeUTypography.subtitle.copyWith(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipOval(
            child: SizedBox.expand(
              child: (imageUrl != null && imageUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: (size *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      placeholder: (_, __) => fallback,
                      errorWidget: (_, __, ___) => fallback,
                    )
                  : fallback,
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeeUColors.success,
                  border: Border.all(color: c.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Единая строка-список (пользователь/трек/файл): плоская, с hairline снизу —
/// вместо трёх конкурирующих стилей (карточки с тенью / Material `ListTile` /
/// hairline-строки).
class SeeUListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// Мелкая mono-метка над заголовком (капс).
  final String? kicker;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool hairline;
  final EdgeInsetsGeometry padding;

  const SeeUListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.kicker,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.hairline = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.faded(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          border: hairline
              ? Border(bottom: BorderSide(color: c.line, width: 0.5))
              : null,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (kicker != null && kicker!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        kicker!.toUpperCase(),
                        style:
                            SeeUTypography.kicker.copyWith(color: c.ink3),
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.subtitle.copyWith(color: c.ink),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            SeeUTypography.caption.copyWith(color: c.ink2),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
