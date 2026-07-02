import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/audio/audio_player_service.dart';
import '../core/design/tokens.dart';
import '../core/design/tappable.dart';
import 'full_screen_player.dart';
import 'mini_player.dart';

/// Global notifier for hiding bottom nav from within a screen (e.g., feed camera swipe).
final bottomNavHiddenNotifier = ValueNotifier<bool>(false);

Widget _navIcon(String name, bool filled) => CustomPaint(
      size: const Size(22, 22),
      painter: _NavIconPainter(name: name, filled: filled),
    );

// ─── Shell scaffold ──────────────────────────────────────────────────────────

class MainScaffold extends StatelessWidget {
  final Widget child;
  final bool showTabs;

  const MainScaffold({
    super.key,
    required this.child,
    required this.showTabs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      extendBody: true,
      bottomNavigationBar: _SeeUBottomArea(showTabs: showTabs),
    );
  }
}

// ─── Stable bottom area ──────────────────────────────────────────────────────

class _SeeUBottomArea extends ConsumerStatefulWidget {
  final bool showTabs;
  const _SeeUBottomArea({required this.showTabs});

  @override
  ConsumerState<_SeeUBottomArea> createState() => _SeeUBottomAreaState();
}

class _SeeUBottomAreaState extends ConsumerState<_SeeUBottomArea> {
  @override
  void initState() {
    super.initState();
    bottomNavHiddenNotifier.addListener(_onHiddenChanged);
  }

  @override
  void dispose() {
    bottomNavHiddenNotifier.removeListener(_onHiddenChanged);
    super.dispose();
  }

  void _onHiddenChanged() => setState(() {});

  static int _locationToIndex(String loc) {
    if (loc.startsWith('/feed')) return 0;
    if (loc.startsWith('/explore')) return 1;
    if (loc.startsWith('/scanner')) return 2;
    if (loc.startsWith('/services') ||
        loc.startsWith('/music') ||
        loc.startsWith('/files') ||
        loc.startsWith('/sbory')) {
      return 3;
    }
    if (loc.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTabTap(int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/scanner', '/services', '/profile'];
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    if (bottomNavHiddenNotifier.value) return const SizedBox.shrink();

    // NB: a plain `.watch(...).track` instead of `.select((s) => s.track)` —
    // the selector form crashed in AOT/release ("Null check operator used on a
    // null value" inside Riverpod's _SelectorSubscription.read), taking the
    // whole bottom nav bar down so navigation stopped working on Android.
    final track = ref.watch(miniPlayerProvider).track;
    final hasMiniPlayer = track != null;
    final showTabs = widget.showTabs;

    if (!hasMiniPlayer && !showTabs) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = showTabs
        ? _locationToIndex(GoRouterState.of(context).matchedLocation)
        : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMiniPlayer)
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              showTabs ? 0 : 6,
              0,
              showTabs ? 6 : MediaQuery.of(context).padding.bottom + 6,
            ),
            child: SeeUMiniPlayer(onTap: () => showFullScreenPlayer(context)),
          ),
        if (showTabs) _buildTabBar(context, isDark, currentIndex),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context, bool isDark, int currentIndex) {
    // Frosted bottom nav — same glass recipe as camera_top_bar: a real
    // backdrop-blur behind a soft theme-aware gradient (light highlight → tint)
    // and a thin top hairline. Reads as one glass stack with the mini-player
    // floating above it (no opaque seam).
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.10),
                      SeeUColors.darkBg.withValues(alpha: 0.82),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.55),
                      SeeUColors.background.withValues(alpha: 0.85),
                    ],
            ),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : SeeUColors.borderSubtle.withValues(alpha: 0.7),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: _navIcon('feed', false),
                activeIcon: _navIcon('feed', true),
                label: 'Лента',
                isSelected: currentIndex == 0,
                onTap: () => _onTabTap(0),
              ),
              _NavItem(
                icon: _navIcon('search', false),
                activeIcon: _navIcon('search', true),
                label: 'Интересное',
                isSelected: currentIndex == 1,
                onTap: () => _onTabTap(1),
              ),
              _ScannerPill(
                isSelected: currentIndex == 2,
                onTap: () => _onTabTap(2),
              ),
              _NavItem(
                icon: _navIcon('services', false),
                activeIcon: _navIcon('services', true),
                label: 'Сервисы',
                isSelected: currentIndex == 3,
                onTap: () => _onTabTap(3),
              ),
              _NavItem(
                icon: _navIcon('user', false),
                activeIcon: _navIcon('user', true),
                label: 'Профиль',
                isSelected: currentIndex == 4,
                onTap: () => _onTabTap(4),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Scanner pill (center tab — USP) ─────────────────────────────────────

class _ScannerPill extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _ScannerPill({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.88,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeeUColors.accentSecondary, SeeUColors.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: isSelected ? 0.55 : 0.35),
              blurRadius: isSelected ? 20 : 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(24, 24),
            painter: _ScannerCenterIcon(active: isSelected),
          ),
        ),
      ),
    );
  }
}

class _ScannerCenterIcon extends CustomPainter {
  final bool active;
  const _ScannerCenterIcon({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.0 : 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.38),
      -2.4, 4.8, false, paint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.22),
      -2.4, 4.8, false, paint);

    canvas.drawCircle(center, s * 0.08,
      Paint()..color = Colors.white..style = PaintingStyle.fill);

    final endX = center.dx + s * 0.38 * 0.62;
    final endY = center.dy - s * 0.38 * 0.78;
    canvas.drawLine(center, Offset(endX, endY),
      Paint()
        ..color = Colors.white
        ..strokeWidth = active ? 2.0 : 1.6
        ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ScannerCenterIcon old) => old.active != active;
}

// ─── Nav item ────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final Widget icon;
  final Widget activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  bool _wasSelected = false;

  @override
  void initState() {
    super.initState();
    _wasSelected = widget.isSelected;
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_bounceController);
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !_wasSelected) {
      _bounceController.forward(from: 0);
    }
    _wasSelected = widget.isSelected;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = SeeUColors.accent;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : SeeUColors.textTertiary;

    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.85,
      child: SizedBox(
        width: 50,
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _bounceAnimation,
              builder: (context, child) {
                final scale =
                    widget.isSelected ? _bounceAnimation.value : 1.0;
                final effectiveScale =
                    widget.isSelected && !_bounceController.isAnimating
                        ? 1.1
                        : scale;
                return Transform.scale(
                  scale: effectiveScale,
                  child: child,
                );
              },
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  widget.isSelected ? activeColor : inactiveColor,
                  BlendMode.srcIn,
                ),
                child: widget.isSelected ? widget.activeIcon : widget.icon,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: SeeUTypography.micro.copyWith(
                fontSize: 9,
                fontWeight:
                    widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                color: widget.isSelected ? activeColor : inactiveColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.isSelected ? 4 : 0,
              height: widget.isSelected ? 4 : 0,
              decoration: const BoxDecoration(
                color: SeeUColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Nav icon painter ────────────────────────────────────────────────────

class _NavIconPainter extends CustomPainter {
  final String name;
  final bool filled;

  _NavIconPainter({required this.name, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = filled ? 2.0 : 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      // «Лента» — стопка карточек (feed). Крупная передняя карточка + два
      // верхних края карточек, лежащих позади и сужающихся кверху → читается
      // как колода/поток постов. Контур = неактивна, залив = активна.
      case 'feed':
        // Верхние края двух карточек в стопке позади (рисуем первыми — они
        // должны оказаться «за» передней карточкой по z-порядку).
        final deckPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = filled ? 2.4 : 1.7
          ..strokeCap = StrokeCap.round;
        // Самая дальняя (верхняя, у́же всех).
        canvas.drawLine(
          Offset(s * 0.32, s * 0.22), Offset(s * 0.68, s * 0.22), deckPaint);
        // Средняя.
        canvas.drawLine(
          Offset(s * 0.24, s * 0.32), Offset(s * 0.76, s * 0.32), deckPaint);

        // Передняя карточка — крупный скруглённый прямоугольник.
        final cardRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.13, s * 0.42, s * 0.74, s * 0.44),
          Radius.circular(s * 0.11),
        );
        canvas.drawRRect(
          cardRect,
          paint
            ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = filled ? 2.0 : 1.7,
        );
        break;

      case 'search':
        final searchCenter = Offset(s * 0.42, s * 0.42);
        final searchR = s * 0.28;

        canvas.drawCircle(
          searchCenter,
          searchR,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.0 : 1.7,
        );
        canvas.drawLine(
          Offset(s * 0.63, s * 0.63),
          Offset(s * 0.86, s * 0.86),
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.4 : 1.7,
        );

        {
          final sc = searchCenter;
          final starPaint = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill;
          final armLong = s * 0.11;
          final armShort = s * 0.045;
          final starPath = Path();
          starPath.moveTo(sc.dx, sc.dy - armLong);
          starPath.quadraticBezierTo(sc.dx + armShort, sc.dy - armShort,
              sc.dx + armLong, sc.dy);
          starPath.quadraticBezierTo(sc.dx + armShort, sc.dy + armShort,
              sc.dx, sc.dy + armLong);
          starPath.quadraticBezierTo(sc.dx - armShort, sc.dy + armShort,
              sc.dx - armLong, sc.dy);
          starPath.quadraticBezierTo(sc.dx - armShort, sc.dy - armShort,
              sc.dx, sc.dy - armLong);
          starPath.close();
          canvas.drawPath(starPath, starPaint);
        }
        break;

      case 'radar':
        final center = Offset(s * 0.5, s * 0.5);
        final arcPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = filled ? 2.0 : 1.7
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.38),
          -2.4, 4.8, false, arcPaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.24),
          -2.4, 4.8, false, arcPaint,
        );
        canvas.drawCircle(
          center,
          s * 0.07,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );

        {
          final endX = center.dx + s * 0.38 * 0.6216;
          final endY = center.dy - s * 0.38 * 0.7833;
          canvas.drawLine(
            center,
            Offset(endX, endY),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = filled ? 2.0 : 1.7
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(endX, endY),
            s * 0.055,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        }
        break;

      case 'services':
        final gap = s * 0.08;
        final cellSize = (s * 0.8 - gap) / 2;
        final left = s * 0.1;
        final top2 = s * 0.1;
        final r = Radius.circular(s * 0.08);
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        paint.strokeWidth = filled ? 1.8 : 1.7;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top2, cellSize, cellSize), r), paint);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(left + cellSize + gap, top2, cellSize, cellSize), r), paint);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top2 + cellSize + gap, cellSize, cellSize), r), paint);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(left + cellSize + gap, top2 + cellSize + gap, cellSize, cellSize), r), paint);
        break;

      case 'user':
        canvas.drawCircle(
          Offset(s * 0.5, s * 0.32),
          s * 0.19,
          paint
            ..style =
                filled ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = filled ? 2.0 : 1.7,
        );
        final bodyPath = Path();
        bodyPath.moveTo(s * 0.14, s * 0.88);
        bodyPath.cubicTo(
          s * 0.14, s * 0.56,
          s * 0.30, s * 0.54,
          s * 0.50, s * 0.54,
        );
        bodyPath.cubicTo(
          s * 0.70, s * 0.54,
          s * 0.86, s * 0.56,
          s * 0.86, s * 0.88,
        );
        if (filled) {
          bodyPath.close();
          canvas.drawPath(
            bodyPath,
            paint
              ..style = PaintingStyle.fill
              ..strokeWidth = 2.0,
          );
        } else {
          canvas.drawPath(
            bodyPath,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7,
          );
        }
        break;

      case 'reels':
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.1, s * 0.8, s * 0.8),
          Radius.circular(s * 0.15),
        );
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        paint.strokeWidth = 1.7;
        canvas.drawRRect(rect, paint);

        final dotPaint = Paint()
          ..color = Colors.white
          ..style = filled ? PaintingStyle.stroke : PaintingStyle.fill;
        dotPaint.strokeWidth = 1.2;
        for (var i = 0; i < 3; i++) {
          final x = s * (0.28 + i * 0.22);
          canvas.drawCircle(Offset(x, s * 0.21), s * 0.035, dotPaint);
          canvas.drawCircle(Offset(x, s * 0.79), s * 0.035, dotPaint);
        }

        if (!filled) {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.fill);
        } else {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeJoin = StrokeJoin.round);
        }
        break;

      case 'video':
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.08, s * 0.2, s * 0.84, s * 0.6),
          const Radius.circular(3),
        );
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        canvas.drawRRect(rect, paint);
        if (!filled) {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.65, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, paint..style = PaintingStyle.fill);
        }
        break;

      case 'folder':
        final folderPath = Path()
          ..moveTo(s * 0.08, s * 0.3)
          ..lineTo(s * 0.08, s * 0.8)
          ..quadraticBezierTo(s * 0.08, s * 0.88, s * 0.16, s * 0.88)
          ..lineTo(s * 0.84, s * 0.88)
          ..quadraticBezierTo(s * 0.92, s * 0.88, s * 0.92, s * 0.8)
          ..lineTo(s * 0.92, s * 0.35)
          ..quadraticBezierTo(s * 0.92, s * 0.27, s * 0.84, s * 0.27)
          ..lineTo(s * 0.52, s * 0.27)
          ..lineTo(s * 0.42, s * 0.15)
          ..lineTo(s * 0.16, s * 0.15)
          ..quadraticBezierTo(s * 0.08, s * 0.15, s * 0.08, s * 0.23)
          ..close();
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        canvas.drawPath(folderPath, paint);
        break;

      case 'music':
        final notePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.save();
        canvas.translate(s * 0.25, s * 0.72);
        canvas.scale(1.0, 0.65);
        canvas.drawCircle(Offset.zero, s * 0.16, notePaint);
        canvas.restore();
        canvas.drawLine(
          Offset(s * 0.40, s * 0.72),
          Offset(s * 0.40, s * 0.18),
          Paint()
            ..color = Colors.white
            ..strokeWidth = filled ? 2.2 : 1.8
            ..strokeCap = StrokeCap.round,
        );
        final flagPath = Path()
          ..moveTo(s * 0.40, s * 0.18)
          ..cubicTo(
            s * 0.68, s * 0.18,
            s * 0.72, s * 0.38,
            s * 0.60, s * 0.52,
          );
        canvas.drawPath(
          flagPath,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.2 : 1.8
            ..strokeCap = StrokeCap.round,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) =>
      name != old.name || filled != old.filled;
}
