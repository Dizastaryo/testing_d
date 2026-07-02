import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/services/video_pip_service.dart';

/// Floating mini-player shown after a video PiP session ends.
/// Placed in main.dart builder so it overlays the entire app.
class VideoMiniPlayerOverlay extends ConsumerWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const VideoMiniPlayerOverlay({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(videoPipProvider.select((s) => s.showMiniPlayer));
    final video = ref.watch(videoPipProvider.select((s) => s.video));

    return Stack(
      children: [
        child,
        if (show && video != null)
          Positioned(
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 90,
            child: _VideoMiniCard(
              video: video,
              // Tapping just dismisses: the dedicated long-video watch page was
              // removed with the Видеотека section, so there's nothing to expand
              // back into. The mini-player still surfaces feed/Shorts PiP state.
              onTap: () => ref.read(videoPipProvider.notifier).dismissMiniPlayer(),
              onClose: () => ref.read(videoPipProvider.notifier).dismissMiniPlayer(),
            ),
          ),
      ],
    );
  }
}

class _VideoMiniCard extends StatelessWidget {
  final VideoInfo video;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _VideoMiniCard({
    required this.video,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          boxShadow: SeeUShadows.lg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail — стекло-кнопки блюрят его как «медиа» под собой.
            if (video.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: SeeUColors.surface2),
              )
            else
              Container(color: SeeUColors.surface2),

            // Scrim снизу — под подпись.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, SeeUColors.darkScrim],
                ),
              ),
            ),

            // Стеклянный play по центру.
            Center(
              child: SeeUGlassCircleButton(
                size: 44,
                icon: Icon(PhosphorIconsFill.play,
                    color: Colors.white, size: 18),
                onTap: onTap,
              ),
            ),

            // Подпись «СЕЙЧАС ИГРАЕТ» + название.
            Positioned(
              left: SeeUSpacing.sm,
              right: 34,
              bottom: SeeUSpacing.sm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'СЕЙЧАС ИГРАЕТ',
                    style: SeeUTypography.kicker.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 8,
                    ),
                  ),
                  if (video.title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.micro.copyWith(color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),

            // Стеклянная close-кнопка.
            Positioned(
              top: SeeUSpacing.xs + 2,
              right: SeeUSpacing.xs + 2,
              child: SeeUGlassCircleButton(
                size: 26,
                icon: Icon(PhosphorIconsBold.x, color: Colors.white, size: 12),
                onTap: onClose,
              ),
            ),

            // Accent-край сверху — фирменный градиент.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [SeeUColors.accent, SeeUColors.accentSecondary],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
