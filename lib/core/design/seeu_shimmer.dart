import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'tokens.dart';

class SeeUShimmer extends StatelessWidget {
  final Widget child;

  const SeeUShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: SeeUColors.surface,
      highlightColor: SeeUColors.surfaceElevated,
      period: const Duration(milliseconds: 1500),
      child: child,
    );
  }
}

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: SeeUColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Default list-row skeleton — single source of truth for screens that
/// were spinning a `CircularProgressIndicator` on initial-list load.
///
/// Layout: avatar (44×44 pill) + title bar (60% width) + subtitle bar
/// (40% width). Repeated `count` times. Mirrors the avatar/title/subtitle
/// shape of music tracks, notifications, followers/following lists.
///
/// Use as a drop-in replacement for `Center(child: CircularProgressIndicator())`
/// in `.when(loading: ...)` callbacks.
class SeeUListSkeleton extends StatelessWidget {
  final int count;
  const SeeUListSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: count,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: const [
              ShimmerBox(width: 44, height: 44, radius: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 180, height: 12, radius: 6),
                    SizedBox(height: 8),
                    ShimmerBox(width: 120, height: 10, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
