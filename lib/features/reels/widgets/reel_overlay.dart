import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/tokens.dart';
import '../../../core/models/post.dart';
import '../../../core/utils/format.dart';

/// TikTok-style overlay: right action column + bottom info panel.
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
        // Bottom gradient
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ),

        // Right action column
        Positioned(
          right: 12,
          bottom: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: post.author.avatarUrl != null && post.author.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: post.author.avatarUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _avatarPlaceholder(),
                          )
                        : _avatarPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Like
              _ActionBtn(
                icon: isLiked
                    ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                    : PhosphorIcons.heart(),
                color: isLiked ? SeeUColors.like : Colors.white,
                label: formatCount(post.likesCount),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onLike();
                },
              ),
              const SizedBox(height: 16),

              // Comment
              _ActionBtn(
                icon: PhosphorIcons.chatCircle(),
                color: Colors.white,
                label: formatCount(post.commentsCount),
                onTap: onComment,
              ),
              const SizedBox(height: 16),

              // Share
              _ActionBtn(
                icon: PhosphorIcons.shareFat(),
                color: Colors.white,
                label: '',
                onTap: onShare,
              ),
              const SizedBox(height: 16),

              // Save
              _ActionBtn(
                icon: isSaved
                    ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                    : PhosphorIcons.bookmarkSimple(),
                color: isSaved ? SeeUColors.accent : Colors.white,
                label: '',
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSave();
                },
              ),
            ],
          ),
        ),

        // Bottom info panel
        Positioned(
          left: 16, right: 80, bottom: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Username
              Text(
                '@${post.author.username}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              if (post.caption != null && post.caption!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  post.caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ],
              if (post.audioTrackId != null && post.audioTrackId!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(PhosphorIcons.musicNote(PhosphorIconsStyle.fill),
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Оригинальный звук',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: Colors.grey.shade800,
      child: Icon(PhosphorIcons.user(), color: Colors.white54, size: 24),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48, height: 48,
              child: Icon(icon, color: color, size: 28),
            ),
            if (label.isNotEmpty)
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                  )),
          ],
        ),
      ),
    );
  }
}
