import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/video_provider.dart';
import 'fullscreen_video_player.dart';

/// Vertical full-screen viewer for a Short opened from Explore.
///
/// Shorts are vertical (9:16) videos. This screen resolves the
/// video by id (the Explore card only carries the id) and hands its playback URL
/// to [FullscreenVideoPlayer] — the same swipe-to-dismiss, looping vertical
/// player used elsewhere — so the clip fills the screen the way reels do.
class ShortViewerScreen extends ConsumerWidget {
  final String videoId;
  const ShortViewerScreen({super.key, required this.videoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(singleVideoProvider(videoId));
    return async.when(
      data: (video) => FullscreenVideoPlayer(
        url: video.playbackUrl,
        videoId: video.id,
        title: video.title,
        thumbnailUrl: video.thumbnailUrl,
      ),
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2.5),
        ),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Theme(
              data: ThemeData(brightness: Brightness.dark),
              child: SeeUErrorState(
                title: 'Не удалось загрузить видео',
                icon: PhosphorIconsRegular.warningCircle,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: SeeUGlassCircleButton(
                icon: PhosphorIcon(PhosphorIconsRegular.x,
                    color: Colors.white, size: 20),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
