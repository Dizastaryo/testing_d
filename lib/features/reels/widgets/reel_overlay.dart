import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/post.dart';
import '../../../core/utils/format.dart';

/// TikTok-style overlay: right glass action column + bottom glass info card.
///
/// Всё, что плавает поверх видео, — настоящее стекло (backdrop-blur): круглые
/// action-кнопки ([SeeUGlassCircleButton]) и нижняя инфо-карта. Music-pill —
/// плоский вложенный чип внутри карты (без своего блюра, «нет стекла на стекле»).
class ReelOverlay extends StatelessWidget {
  final Post post;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onAvatarTap;

  const ReelOverlay({
    super.key,
    required this.post,
    required this.isLiked,
    required this.isSaved,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Bottom scrim — держит контраст текста над яркими кадрами.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.42,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, SeeUColors.darkScrim],
                ),
              ),
            ),
          ),
        ),

        // Right action column — стеклянные круги.
        Positioned(
          right: SeeUSpacing.md,
          bottom: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar — accent-ring, брендовый «автор».
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: SeeUColors.accent, width: 2),
                  ),
                  child: ClipOval(
                    child: post.author.avatarUrl != null &&
                            post.author.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: post.author.avatarUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _avatarPlaceholder(),
                          )
                        : _avatarPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(height: SeeUSpacing.lg),

              _ActionBtn(
                icon: isLiked
                    ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                    : PhosphorIcons.heart(),
                iconColor: isLiked ? SeeUColors.like : Colors.white,
                label: formatCount(post.likesCount),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onLike();
                },
              ),
              const SizedBox(height: SeeUSpacing.base),

              _ActionBtn(
                icon: PhosphorIcons.chatCircle(),
                iconColor: Colors.white,
                label: formatCount(post.commentsCount),
                onTap: onComment,
              ),
              const SizedBox(height: SeeUSpacing.base),

              _ActionBtn(
                icon: PhosphorIcons.shareFat(),
                iconColor: Colors.white,
                label: '',
                onTap: onShare,
              ),
              const SizedBox(height: SeeUSpacing.base),

              _ActionBtn(
                icon: isSaved
                    ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                    : PhosphorIcons.bookmarkSimple(),
                iconColor: isSaved ? SeeUColors.accent : Colors.white,
                label: '',
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSave();
                },
              ),
            ],
          ),
        ),

        // Bottom info card — одна стеклянная панель (blur 28).
        Positioned(
          left: SeeUSpacing.base,
          right: 80,
          bottom: 48,
          child: _InfoCard(post: post),
        ),
      ],
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: SeeUColors.surface2,
      child: Icon(PhosphorIcons.user(),
          color: Colors.white.withValues(alpha: 0.6), size: 24),
    );
  }
}

/// Круглая стеклянная action-кнопка + подпись-счётчик под ней.
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeeUGlassCircleButton(
          size: 48,
          icon: Icon(icon, color: iconColor, size: 26),
          onTap: onTap,
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: SeeUSpacing.xs + 2),
          Text(
            label,
            style: SeeUTypography.micro.copyWith(color: Colors.white),
          ),
        ],
      ],
    );
  }
}

/// Нижняя стеклянная инфо-карта: editorial-автор + подпись + music-pill.
class _InfoCard extends StatelessWidget {
  final Post post;
  const _InfoCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final hasCaption = post.caption != null && post.caption!.isNotEmpty;
    final hasAudio =
        post.audioTrackId != null && post.audioTrackId!.isNotEmpty;
    final fullName = post.author.fullName.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.card),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SeeUSpacing.md, vertical: SeeUSpacing.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.30),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.card),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Автор — Fraunces-имя + @handle mono kicker.
              Text(
                fullName.isNotEmpty ? fullName : '@${post.author.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeeUTypography.displayS.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              if (fullName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '@${post.author.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              if (hasCaption) ...[
                const SizedBox(height: SeeUSpacing.sm),
                Text(
                  post.caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                  ),
                ),
              ],
              if (hasAudio) ...[
                const SizedBox(height: SeeUSpacing.md),
                _MusicPill(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Плоский вложенный music-чип (без своего блюра — внутри стеклянной карты).
class _MusicPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.musicNote(PhosphorIconsStyle.fill),
              color: Colors.white, size: 13),
          const SizedBox(width: SeeUSpacing.sm),
          Flexible(
            child: Text(
              'Оригинальный звук',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeeUTypography.mono.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
