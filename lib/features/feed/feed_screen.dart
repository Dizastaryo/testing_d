import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/design/design.dart';
import '../../core/providers/feed_provider.dart';
import '../../core/providers/notification_provider.dart';
import '../camera/camera_screen.dart';
import '../../widgets/main_scaffold.dart' show bottomNavHiddenNotifier;
import 'widgets/stories_row.dart';
import 'widgets/post_card.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;
  bool _dailyPromptDismissed = false;

  // PageView for camera swipe
  late PageController _pageController;
  bool _isCameraActive = false;
  bool _cameraEverOpened = false;

  // Header icon entrance animations
  late AnimationController _headerIconsController;
  late Animation<double> _icon1Fade;
  late Animation<Offset> _icon1Slide;
  late Animation<double> _icon2Fade;
  late Animation<Offset> _icon2Slide;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _scrollController.addListener(_onScroll);

    // Header icons entrance animation controller
    _headerIconsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // First icon: 0ms - 300ms
    _icon1Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerIconsController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _icon1Slide = Tween<Offset>(
      begin: const Offset(20, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _headerIconsController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Second icon: 100ms offset -> ~0.2 - 0.8 of total
    _icon2Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerIconsController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
    _icon2Slide = Tween<Offset>(
      begin: const Offset(20, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _headerIconsController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // Start entrance animation
    _headerIconsController.forward();
  }

  @override
  void dispose() {
    bottomNavHiddenNotifier.value = false;
    _scrollController.dispose();
    _pageController.dispose();
    _headerIconsController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    final isCamera = page == 0;
    if (isCamera != _isCameraActive) {
      setState(() {
        _isCameraActive = isCamera;
        if (isCamera) _cameraEverOpened = true;
      });
      bottomNavHiddenNotifier.value = isCamera;
      if (isCamera) {
        HapticFeedback.mediumImpact();
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
        ));
      } else {
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ));
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(feedProvider.notifier).loadMore();
    }

    // Show/hide scroll-to-top button
    final shouldShow = _scrollController.position.pixels > 500;
    if (shouldShow != _showScrollToTop) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onRefresh() async {
    await ref.read(feedProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    final notifState = ref.watch(notificationProvider);

    return PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      children: [
        // Page 0: Camera (lazy — only build when first swiped to)
        _cameraEverOpened
            ? CameraScreen(
                onClose: () {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                },
              )
            : const ColoredBox(color: Colors.black),
        // Page 1: Feed
        _buildFeedPage(feedState, notifState),
      ],
    );
  }

  Widget _buildFeedPage(dynamic feedState, dynamic notifState) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          feedState.isLoading && feedState.posts.isEmpty
              ? _buildShimmer()
              : feedState.error != null && feedState.posts.isEmpty
                  ? _buildError(feedState.error!)
                  : RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: SeeUColors.accent,
                  child: feedState.posts.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [SizedBox(height: MediaQuery.of(context).size.height * 0.3), _buildEmpty()],
                        )
                      : CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Custom header
                            SliverToBoxAdapter(
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      18, 12, 18, 12),
                                  child: Row(
                                    children: [
                                      // EyeMark + Gradient "SeeU" header
                                      Row(
                                        children: [
                                          const _EyeMarkLogo(size: 26),
                                          const SizedBox(width: 8),
                                          ShaderMask(
                                            shaderCallback: (bounds) =>
                                                SeeUColors.titleGradient
                                                    .createShader(bounds),
                                            blendMode: BlendMode.srcIn,
                                            child: Text(
                                              'SeeU',
                                              style: SeeUTypography.displayL
                                                  .copyWith(
                                                      color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      // DM button with entrance animation
                                      AnimatedBuilder(
                                        animation: _headerIconsController,
                                        builder: (context, child) {
                                          return Transform.translate(
                                            offset: _icon1Slide.value,
                                            child: Opacity(
                                              opacity: _icon1Fade.value,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: _HeaderIconButton(
                                          icon: PhosphorIcon(
                                              PhosphorIcons
                                                  .chatCircleDots()),
                                          onTap: () => context.push('/chat'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Bell button with staggered entrance
                                      AnimatedBuilder(
                                        animation: _headerIconsController,
                                        builder: (context, child) {
                                          return Transform.translate(
                                            offset: _icon2Slide.value,
                                            child: Opacity(
                                              opacity: _icon2Fade.value,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: _HeaderIconButton(
                                          icon: PhosphorIcon(
                                              PhosphorIcons.bell()),
                                          badge: notifState.unreadCount,
                                          onTap: () =>
                                              context.push('/notifications'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _HeaderIconButton(
                                        icon: PhosphorIcon(
                                            PhosphorIcons.userCircle()),
                                        onTap: () =>
                                            context.push('/profile'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: StoriesRow()),
                            if (!_dailyPromptDismissed)
                              SliverToBoxAdapter(child: _DailyPromptCard(
                                onDismiss: () => setState(() => _dailyPromptDismissed = true),
                              )),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == feedState.posts.length) {
                                    return feedState.isLoadingMore
                                        ? _buildLoadingMore()
                                        : const SizedBox(height: 100);
                                  }
                                  return AnimationConfiguration
                                      .staggeredList(
                                    position: index,
                                    duration:
                                        const Duration(milliseconds: 400),
                                    delay:
                                        const Duration(milliseconds: 50),
                                    child: SlideAnimation(
                                      verticalOffset: 30,
                                      curve: Curves.easeOutCubic,
                                      child: FadeInAnimation(
                                        curve: Curves.easeOutCubic,
                                        child: PostCard(
                                            post: feedState.posts[index]),
                                      ),
                                    ),
                                  );
                                },
                                childCount: feedState.posts.length + 1,
                              ),
                            ),
                          ],
                        ),
                ),
          // Scroll-to-top FAB

          Positioned(
            bottom: 88,
            right: 20,
            child: AnimatedOpacity(
              opacity: _showScrollToTop ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: _showScrollToTop ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: IgnorePointer(
                  ignoring: !_showScrollToTop,
                  child: GestureDetector(
                    onTap: _scrollToTop,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.surface,
                        shape: BoxShape.circle,
                        boxShadow: SeeUShadows.md,
                        border: Border.all(
                          color: SeeUColors.accent.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: PhosphorIcon(
                          PhosphorIconsRegular.arrowUp,
                          size: 20,
                          color: SeeUColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: _DotPulse(color: SeeUColors.accent),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return SafeArea(
      child: SeeUShimmer(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header shimmer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    ShimmerBox(width: 80, height: 32, radius: SeeURadii.small),
                    const Spacer(),
                    ShimmerBox(width: 40, height: 40, radius: SeeURadii.pill),
                    const SizedBox(width: 10),
                    ShimmerBox(width: 40, height: 40, radius: SeeURadii.pill),
                  ],
                ),
              ),
              // Stories shimmer
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: 6,
                  itemBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShimmerBox(
                            width: 68, height: 68, radius: SeeURadii.pill),
                        const SizedBox(height: 5),
                        ShimmerBox(width: 52, height: 10, radius: 5),
                      ],
                    ),
                  ),
                ),
              ),
              // Post shimmer items
              ...List.generate(
                3,
                (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ShimmerBox(
                              width: 36, height: 36, radius: SeeURadii.pill),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerBox(
                                  width: 120,
                                  height: 12,
                                  radius: SeeURadii.small),
                              const SizedBox(height: 4),
                              ShimmerBox(
                                  width: 80,
                                  height: 10,
                                  radius: SeeURadii.small),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ShimmerBox(
                          width: double.infinity,
                          height: 300,
                          radius: SeeURadii.card),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // U08: Error state with retry button
  Widget _buildError(String error) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIcons.wifiSlash(),
              size: 56,
              color: c.ink3,
            ),
            const SizedBox(height: 16),
            Text(
              'Не удалось загрузить ленту',
              style: SeeUTypography.subtitle
                  .copyWith(color: c.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: SeeUTypography.caption
                  .copyWith(color: c.ink3),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            SeeUButton(
              label: 'Повторить',
              onTap: _onRefresh,
              icon: PhosphorIcons.arrowCounterClockwise(),
            ),
          ],
        ),
      ),
    );
  }

  // U09: Meaningful empty state with icon + CTA
  Widget _buildEmpty() {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIcons.usersThree(),
              size: 64,
              color: c.line,
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет постов',
              style: SeeUTypography.subtitle
                  .copyWith(color: c.ink2),
            ),
            const SizedBox(height: 6),
            Text(
              'Подпишитесь на людей, чтобы видеть их посты',
              style: SeeUTypography.caption
                  .copyWith(color: c.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SeeUButton(
              label: 'Найти людей',
              onTap: () => context.go('/explore'),
              icon: PhosphorIcons.magnifyingGlass(),
            ),
          ],
        ),
      ),
    );
  }

}

// ─── Header icon button ──────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final Widget icon;
  final int badge;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                color: c.line,
                width: 0.5,
              ),
            ),
            child: Center(
              child: IconTheme(
                data: IconThemeData(
                    size: 20, color: c.ink),
                child: icon,
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: SeeUColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badge > 9 ? '9+' : badge.toString(),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── EyeMark logo (matches design) ───────────────────────────────────────

class _EyeMarkLogo extends StatelessWidget {
  final double size;
  const _EyeMarkLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.3),
          colors: [Color(0xFFFF8060), Color(0xFFFF5A3C)],
        ),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _EyeMarkPainter(),
      ),
    );
  }
}

class _EyeMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    // White eye shape
    final eyePath = Path();
    eyePath.moveTo(s * 0.12, s / 2);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.2, s / 2, s * 0.2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.2, s * 0.88, s / 2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.8, s / 2, s * 0.8);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.8, s * 0.12, s / 2);
    eyePath.close();
    canvas.drawPath(
      eyePath,
      Paint()..color = const Color(0xFFFFF6F0),
    );

    // Iris gradient
    final irisPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        colors: [const Color(0xFFFF6E50), const Color(0xFFC12A1A)],
      ).createShader(Rect.fromCircle(center: center, radius: s * 0.18));
    canvas.drawCircle(center, s * 0.18, irisPaint);

    // Highlight
    canvas.drawCircle(
      Offset(s * 0.44, s * 0.44),
      s * 0.04,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Daily Prompt card ────────────────────────────────────────────────────

class _DailyPromptCard extends StatelessWidget {
  final VoidCallback? onDismiss;
  const _DailyPromptCard({this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 1.0],
            colors: [Color(0xFFFFE4D9), Color(0xFFFFF5D4)],
            transform: GradientRotation(120 * 3.14159 / 180),
          ),
          border: Border.all(color: Color(0xFFFFD7BC), width: 1),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Decorative sparkle in top-right corner
            Positioned(
              right: -10,
              top: -10,
              child: Opacity(
                opacity: 0.3,
                child: CustomPaint(
                  size: const Size(80, 80),
                  painter: _SparklePainter(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "SEEU DAILY" mono label
                  const Text(
                    'SEEU DAILY',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA52512),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Serif question
                  Text(
                    'что вас удивило\nсегодня?',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.15,
                      letterSpacing: -0.02 * 22,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Action buttons
                  Row(
                    children: [
                      _PromptButton(
                        label: 'Снять',
                        isPrimary: true,
                        onTap: () => context.push('/story/create'),
                      ),
                      const SizedBox(width: 8),
                      _PromptButton(
                        label: 'Пропустить',
                        isPrimary: false,
                        onTap: onDismiss,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _PromptButton({
    required this.label,
    required this.isPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: isPrimary ? SeeUColors.accent : Colors.transparent,
          border: isPrimary
              ? null
              : Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.5),
                  width: 1,
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isPrimary ? Colors.white : SeeUColors.accent,
          ),
        ),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final paint = Paint()
      ..color = const Color(0xFFFF5A3C)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // 4-point star sparkle
    const arms = 4;
    for (int i = 0; i < arms; i++) {
      final angle = (i * math.pi * 2 / arms) - math.pi / 2;
      final outerX = center.dx + s * 0.42 * math.cos(angle);
      final outerY = center.dy + s * 0.42 * math.sin(angle);
      final innerAngle = angle + math.pi / arms;
      final innerX = center.dx + s * 0.18 * math.cos(innerAngle);
      final innerY = center.dy + s * 0.18 * math.sin(innerAngle);
      canvas.drawLine(center, Offset(outerX, outerY), paint);
      canvas.drawLine(center, Offset(innerX, innerY), paint);
    }
    canvas.drawCircle(
        center, s * 0.06, Paint()..color = const Color(0xFFFF5A3C));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Dot pulse loading indicator ─────────────────────────────────────────

class _DotPulse extends StatefulWidget {
  final Color color;
  const _DotPulse({required this.color});

  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final delay = i * 0.2;
          final t = (_controller.value - delay) % 1.0;
          final scale = (t < 0.5) ? 0.6 + 0.4 * (t * 2) : 1.0 - 0.4 * ((t - 0.5) * 2);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 6 * scale,
            height: 6 * scale,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.4 + 0.6 * scale),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
