import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/design/design.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/daily_prompt_provider.dart';
import '../../core/providers/feed_provider.dart' show feedProvider;
import '../../core/providers/notification_provider.dart';
import '../camera/camera_screen.dart';
import '../../widgets/main_scaffold.dart' show bottomNavHiddenNotifier;
import 'widgets/stories_row.dart';
import 'widgets/post_card.dart';

// Ключ в SharedPreferences — хранит дату (YYYY-MM-DD, UTC) последнего
// закрытия daily-prompt карточки. Промпт меняется каждый день (см.
// daily_prompt_provider.dart), поэтому дизмисс не «навсегда», а до конца
// текущего дня — на следующий день снова покажется уже с новым текстом.
const _dailyPromptDismissedDateKey = 'daily_prompt_dismissed_date';

String _todayDateKey() {
  final now = DateTime.now().toUtc();
  final mm = now.month.toString().padLeft(2, '0');
  final dd = now.day.toString().padLeft(2, '0');
  return '${now.year}-$mm-$dd';
}

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
    _loadDailyPromptDismissed();

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

  Future<void> _loadDailyPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedDate = prefs.getString(_dailyPromptDismissedDateKey);
    if (mounted && dismissedDate == _todayDateKey()) {
      setState(() => _dailyPromptDismissed = true);
    }
  }

  Future<void> _dismissDailyPrompt() async {
    setState(() => _dailyPromptDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyPromptDismissedDateKey, _todayDateKey());
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

  // (Кнопка «+» из шапки убрана по дизайну §03 — камера открывается свайпом
  // к странице 0 PageView, создание контента живёт в профиле.)

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
                  : SeeURadarRefresh(
                  onRefresh: _onRefresh,
                  child: feedState.posts.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [SizedBox(height: MediaQuery.of(context).size.height * 0.3), _buildEmpty()],
                        )
                      : CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Матовая шапка (blur 28) в самом верху ленты —
                            // не закреплена, уезжает вверх со скроллом.
                            _buildGlassHeader(context, notifState),
                            const SliverToBoxAdapter(child: StoriesRow()),
                            // FEED-3: banner новых постов от подписок.
                            if (feedState.pendingNewCount > 0)
                              SliverToBoxAdapter(
                                child: _NewPostsBanner(
                                  count: feedState.pendingNewCount,
                                  onTap: () async {
                                    HapticFeedback.selectionClick();
                                    await ref
                                        .read(feedProvider.notifier)
                                        .consumePendingAndRefresh();
                                    // Scroll to top после merge.
                                    if (_scrollController.hasClients) {
                                      _scrollController.animateTo(
                                        0,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                ),
                              ),
                            if (!_dailyPromptDismissed)
                              SliverToBoxAdapter(child: _DailyPromptCard(
                                onDismiss: _dismissDailyPrompt,
                              )),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == feedState.posts.length) {
                                    return feedState.isLoadingMore
                                        ? _buildLoadingMore()
                                        : const SizedBox(height: 100);
                                  }
                                  // No staggered entrance animation on feed
                                  // cells: without an AnimationLimiter ancestor
                                  // the slide+fade re-fired on every cell build
                                  // during scroll (flicker/jank). Instagram-style
                                  // feeds don't animate cells on scroll.
                                  final post = feedState.posts[index];
                                  return PostCard(
                                    key: ValueKey(post.id),
                                    post: post,
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
                      width: 44,
                      height: 44,
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

  /// Матовая шапка ленты (blur 28, светлый градиент, hairline снизу). Не
  /// закреплена — уезжает вверх со скроллом, видна только у начала ленты.
  /// Слева — стеклянная кнопка «+» (открывает камеру), по центру — серифный
  /// wordmark «SeeU» с фирменным градиентом, справа — стеклянные кнопки чата и
  /// уведомлений с их staggered-входом.
  Widget _buildGlassHeader(BuildContext context, dynamic notifState) {
    final c = context.seeuColors;
    final topInset = MediaQuery.of(context).padding.top;
    const contentHeight = 60.0;

    // Бренд-wordmark «SeeU» подписным Pacifico, сплошной коралл — как задаёт
    // дизайн-ядро (§03). Без градиента: логотип должен читаться как один
    // фирменный знак, а не как декоративная плашка.
    final wordmark = Text(
      'SeeU',
      style: TextStyle(
        fontFamily: AppFonts.I.brand,
        fontSize: 27,
        height: 1.0,
        color: SeeUColors.accent,
      ),
    );

    // §03: wordmark слева, справа bell (с точкой непрочитанного) и chat.
    // «+» из хедера убран — создание живёт в профиле и свайпе к камере.
    final row = Row(
      children: [
        wordmark,
        const Spacer(),
        // Bell button with staggered entrance
        AnimatedBuilder(
          animation: _headerIconsController,
          builder: (context, child) {
            return Transform.translate(
              offset: _icon1Slide.value,
              child: Opacity(opacity: _icon1Fade.value, child: child),
            );
          },
          child: _HeaderIconButton(
            icon: PhosphorIcon(PhosphorIcons.bell()),
            badge: notifState.unreadCount,
            onTap: () => context.push('/notifications'),
          ),
        ),
        const SizedBox(width: 10),
        // DM button with entrance animation
        AnimatedBuilder(
          animation: _headerIconsController,
          builder: (context, child) {
            return Transform.translate(
              offset: _icon2Slide.value,
              child: Opacity(opacity: _icon2Fade.value, child: child),
            );
          },
          child: Consumer(
            builder: (context, ref, _) {
              final unread = ref.watch(chatListProvider).chats.fold<int>(
                  0, (acc, c) => acc + c.unreadCount);
              return _HeaderIconButton(
                icon: PhosphorIcon(PhosphorIcons.chatCircle()),
                badge: unread,
                onTap: () => context.push('/chat'),
              );
            },
          ),
        ),
      ],
    );

    return SliverPersistentHeader(
      // Не pinned: шапка живёт в самом верху ленты и уезжает вверх вместе с
      // контентом при скролле, а не залипает поверх постов. Видна только когда
      // лента прокручена к началу.
      pinned: false,
      delegate: _FeedHeaderDelegate(
        extent: topInset + contentHeight,
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.14),
                    c.surface.withValues(alpha: 0.72),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: c.line, width: 0.5),
                ),
              ),
              child: row,
            ),
          ),
        ),
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
  Widget _buildError(String error) => SeeUErrorState(
        error: error,
        title: 'Не удалось загрузить ленту',
        onRetry: _onRefresh,
      );

  // §03: пустая лента зовёт в Сканер — «SeeU про близость офлайн».
  Widget _buildEmpty() => SeeUEmptyState(
        icon: PhosphorIconsRegular.usersThree,
        title: 'Пока тихо',
        subtitle: 'Ты ещё ни на кого не подписан. Найди своих рядом — через Сканер.',
        action: SeeUStateAction(
          label: 'Открыть Сканер',
          icon: PhosphorIconsRegular.broadcast,
          onTap: () => context.go('/scanner'),
        ),
      );

}

// ─── Pinned glass header delegate ──────────────────────────────────────────

class _FeedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;

  _FeedHeaderDelegate({required this.extent, required this.child});

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(covariant _FeedHeaderDelegate old) =>
      old.child != child || old.extent != extent;
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
          // Плавающая стеклянная кнопка над лентой (blur 18, светлый градиент).
          ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      c.surface.withValues(alpha: 0.72),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.line,
                    width: 0.5,
                  ),
                ),
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(size: 23, color: c.ink),
                    child: icon,
                  ),
                ),
              ),
            ),
          ),
          // §03: индикатор непрочитанного — точка 8px #FF3B6B с обводкой
          // фоном, не числовой бейдж.
          if (badge > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: SeeUColors.like,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Daily Prompt card ────────────────────────────────────────────────────

class _DailyPromptCard extends ConsumerWidget {
  final VoidCallback? onDismiss;
  const _DailyPromptCard({this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final prompt = ref.watch(dailyPromptProvider).maybeWhen(
          data: (p) => p,
          orElse: () => DailyPrompt.fallback,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 1.0],
            colors: [
              SeeUColors.accentSoft,
              SeeUColors.amber.withValues(alpha: 0.25),
            ],
            transform: const GradientRotation(120 * 3.14159 / 180),
          ),
          border: Border.all(
              color: SeeUColors.accentSecondary.withValues(alpha: 0.4),
              width: 1),
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
                  // "SEEU DAILY" mono kicker
                  Text(
                    'SEEU DAILY',
                    style: SeeUTypography.kicker
                        .copyWith(color: SeeUColors.accent),
                  ),
                  const SizedBox(height: 6),
                  // Serif question (Fraunces)
                  Text(
                    prompt.text,
                    style: SeeUTypography.displayS
                        .copyWith(height: 1.15, color: c.ink),
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
          borderRadius: BorderRadius.circular(SeeURadii.pill),
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
          style: SeeUTypography.caption.copyWith(
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
      ..color = SeeUColors.accent
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
        center, s * 0.06, Paint()..color = SeeUColors.accent);
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

// ===========================================================================
// FEED-3: banner «N новых постов ↑» — появляется когда WS post.created event
// прилетел пока юзер в feed'е. Tap → refresh + scroll-to-top.
// ===========================================================================

class _NewPostsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NewPostsBanner({required this.count, required this.onTap});

  String _pluralPosts(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'новый пост';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'новых поста';
    }
    return 'новых постов';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: SeeUGradients.heroOrange,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PhosphorIcon(PhosphorIconsRegular.arrowUp,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                '$count ${_pluralPosts(count)}',
                style: SeeUTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
