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

/// Message-bubbles skeleton — alternating left/right bubbles, positioned at
/// the bottom of the available space (mirrors reverse-scroll chat).
class SeeUMessagesSkeleton extends StatelessWidget {
  const SeeUMessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // (isRight, widthFraction 0..1)
    const rows = [
      (false, 0.60),
      (true,  0.55),
      (false, 0.75),
      (true,  0.45),
      (false, 0.65),
      (true,  0.50),
    ];
    return SeeUShimmer(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final maxW = constraints.maxWidth;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (isRight, frac) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: isRight
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        if (!isRight) ...[
                          ShimmerBox(width: 32, height: 32, radius: 16),
                          const SizedBox(width: 8),
                        ],
                        ShimmerBox(
                          width: maxW * frac,
                          height: 44,
                          radius: 18,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Room-card skeleton — matches _RoomCard in chat_list_screen.dart.
/// Icon box 48×48 (borderRadius 14) + 3 text lines.
class SeeURoomCardSkeleton extends StatelessWidget {
  final int count;
  const SeeURoomCardSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
          ),
          child: Row(
            children: const [
              ShimmerBox(width: 48, height: 48, radius: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 14, radius: 6),
                    SizedBox(height: 8),
                    ShimmerBox(width: 100, height: 12, radius: 5),
                    SizedBox(height: 6),
                    ShimmerBox(width: 180, height: 11, radius: 5),
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

/// SborCard skeleton — matches SborCard layout: header strip 96px + body.
class SeeUSborCardSkeleton extends StatelessWidget {
  final int count;
  const SeeUSborCardSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            // Beige background so white ShimmerBoxes are visually distinct
            // and the shimmer sweep (white→beige) is clearly animated.
            color: SeeUColors.surfaceElevated,
            borderRadius: BorderRadius.circular(SeeURadii.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image placeholder — height matches SborCard's SizedBox(height: 150)
              ShimmerBox(width: double.infinity, height: 150, radius: 0),
              // Body
              Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: double.infinity, height: 16, radius: 7),
                    SizedBox(height: 8),
                    ShimmerBox(width: 180, height: 12, radius: 5),
                    SizedBox(height: 10),
                    Row(children: [
                      ShimmerBox(width: 24, height: 24, radius: 12),
                      SizedBox(width: 4),
                      ShimmerBox(width: 24, height: 24, radius: 12),
                      SizedBox(width: 4),
                      ShimmerBox(width: 24, height: 24, radius: 12),
                    ]),
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

/// SborDetail skeleton — hero block + 2×2 info grid + description lines.
class SeeUSborDetailSkeleton extends StatelessWidget {
  const SeeUSborDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero
            const ShimmerBox(width: double.infinity, height: 220, radius: 24),
            const SizedBox(height: 16),
            // Grid 2×2
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.65,
              children: List.generate(
                4,
                (_) => const ShimmerBox(
                    width: double.infinity, height: double.infinity, radius: 18),
              ),
            ),
            const SizedBox(height: 16),
            // Description lines
            const ShimmerBox(width: double.infinity, height: 14, radius: 6),
            const SizedBox(height: 8),
            const ShimmerBox(width: double.infinity, height: 14, radius: 6),
            const SizedBox(height: 8),
            const ShimmerBox(width: 200, height: 14, radius: 6),
          ],
        ),
      ),
    );
  }
}

/// Join-request list skeleton — matches _RequestCard layout.
class SeeURequestListSkeleton extends StatelessWidget {
  final int count;
  const SeeURequestListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
          ),
          child: Row(
            children: const [
              ShimmerBox(width: 44, height: 44, radius: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 120, height: 13, radius: 6),
                    SizedBox(height: 6),
                    ShimmerBox(width: 80, height: 11, radius: 5),
                  ],
                ),
              ),
              SizedBox(width: 10),
              ShimmerBox(width: 58, height: 34, radius: 10),
              SizedBox(width: 8),
              ShimmerBox(width: 58, height: 34, radius: 10),
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
