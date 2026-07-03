import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/models/user.dart';
import '../../../widgets/verified_badge.dart';

/// Шапка-идентичность профиля — «паспорт»: прямоугольное фото слева +
/// два подписанных поля справа (ИМЯ / ЛОГИН), вместо привычного большого
/// круглого аватара по центру. Композиция другая, дизайн-система та же
/// (Fraunces/Inter, SeeUColors, SeeURadii) — профиль остаётся частью
/// приложения, просто иначе скомпонован.
class ProfilePassportHeader extends StatelessWidget {
  final User user;
  final bool hasStories;
  final bool hasUnseenStories;
  final VoidCallback? onAvatarTap;

  const ProfilePassportHeader({
    super.key,
    required this.user,
    this.hasStories = false,
    this.hasUnseenStories = false,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Hero(
              tag: 'avatar-${user.username}',
              child: _PassportPhoto(
                user: user,
                hasUnseenStories: hasUnseenStories,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              // Оптически центрируем блок полей относительно высоты фото.
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _PassportField(
                          label: 'ИМЯ',
                          value: displayName,
                          valueStyle: SeeUTypography.displayXS
                              .copyWith(color: c.ink),
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 2),
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: VerifiedBadge(size: 16),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PassportField(
                    label: 'ЛОГИН',
                    value: '@${user.username}',
                    valueStyle:
                        SeeUTypography.subtitle.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassportField extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle valueStyle;

  const _PassportField({
    required this.label,
    required this.value,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: SeeUTypography.kicker.copyWith(color: c.ink4)),
        const SizedBox(height: 2),
        Text(
          value,
          style: valueStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Прямоугольное фото пропорций ID-снимка (не круг). Тонкая рамка:
/// нейтральная — обычное состояние; акцентная — есть непросмотренные сторис
/// (заменяет конический story-ring, который на маленьком прямоугольнике
/// выглядел бы избыточно).
class _PassportPhoto extends StatelessWidget {
  final User user;
  final bool hasUnseenStories;

  const _PassportPhoto({required this.user, this.hasUnseenStories = false});

  static const double _w = 64;
  static const double _h = 84;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(
          color: hasUnseenStories ? SeeUColors.accent : c.line,
          width: hasUnseenStories ? 1.6 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.small - 3),
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: user.avatarUrl!,
                width: _w,
                height: _h,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: c.surface2),
                errorWidget: (_, __, ___) => _placeholder(c),
              )
            : _placeholder(c),
      ),
    );
  }

  Widget _placeholder(SeeUThemeColors c) {
    return Container(
      width: _w,
      height: _h,
      color: c.ink3.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
        style: SeeUTypography.displayXS.copyWith(color: Colors.white),
      ),
    );
  }
}
