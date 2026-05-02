import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/design.dart';

class StoryCircle extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final bool isSeen;
  final bool isOwn;
  final VoidCallback? onTap;
  final double size;

  const StoryCircle({
    super.key,
    this.imageUrl,
    required this.username,
    this.isSeen = false,
    this.isOwn = false,
    this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final showGradientRing = !isSeen && !isOwn;
    final showSeenStyle = isSeen && !isOwn;

    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.93,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // Outer ring container
              // L07: For own story, no ring so use size, not size + 4
              Container(
                width: isOwn ? size : size + 4,
                height: isOwn ? size : size + 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: showGradientRing
                      ? SeeUColors.storyGradient
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(showGradientRing ? 2.0 : 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeeUColors.background,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(showGradientRing ? 2 : 0),
                      child: ClipOval(
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: showSeenStyle
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.mode(
                                      Colors.grey, BlendMode.saturation),
                                  child: Opacity(
                                    opacity: 0.6,
                                    child: _buildAvatar(),
                                  ),
                                )
                              : _buildAvatar(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // "Your story" plus badge
              if (isOwn)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SeeUColors.background,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(PhosphorIcons.plus(),
                          color: Colors.white, size: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          // L08: Use TextOverflow.ellipsis instead of manual _truncateUsername
          SizedBox(
            width: size + 4,
            child: Text(
              isOwn ? 'Ваша история' : username,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeeUTypography.micro.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      color: SeeUColors.surfaceElevated,
      child: Center(
        child: Icon(PhosphorIcons.user(),
            color: SeeUColors.textTertiary, size: 24),
      ),
    );
  }

}
