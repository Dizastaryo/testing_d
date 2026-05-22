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

/// Chat-list skeleton — 52px avatar + two lines + time column (right).
class SeeUChatSkeleton extends StatelessWidget {
  final int count;
  const SeeUChatSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: count,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: const [
              ShimmerBox(width: 52, height: 52, radius: 26),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 13, radius: 6),
                    SizedBox(height: 8),
                    ShimmerBox(width: 200, height: 10, radius: 5),
                  ],
                ),
              ),
              SizedBox(width: 8),
              ShimmerBox(width: 36, height: 10, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post-card skeleton — image placeholder + author row + text lines.
class SeeUPostSkeleton extends StatelessWidget {
  final int count;
  const SeeUPostSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: count,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  ShimmerBox(width: 36, height: 36, radius: 18),
                  SizedBox(width: 10),
                  ShimmerBox(width: 120, height: 12, radius: 6),
                ],
              ),
              const SizedBox(height: 12),
              const ShimmerBox(width: double.infinity, height: 280, radius: 16),
              const SizedBox(height: 12),
              const ShimmerBox(width: 220, height: 11, radius: 5),
              const SizedBox(height: 6),
              const ShimmerBox(width: 160, height: 11, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile skeleton — header + avatar + stats row + grid.
class SeeUProfileSkeleton extends StatelessWidget {
  const SeeUProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            const ShimmerBox(width: 80, height: 80, radius: 40),
            const SizedBox(height: 12),
            const ShimmerBox(width: 140, height: 14, radius: 7),
            const SizedBox(height: 8),
            const ShimmerBox(width: 100, height: 11, radius: 5),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                ShimmerBox(width: 60, height: 36, radius: 8),
                ShimmerBox(width: 60, height: 36, radius: 8),
                ShimmerBox(width: 60, height: 36, radius: 8),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(
                9,
                (_) => const ShimmerBox(width: 110, height: 110, radius: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
