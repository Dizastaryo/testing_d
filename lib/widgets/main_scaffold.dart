import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/design/tokens.dart';
import '../core/design/tappable.dart';

/// Global notifier for hiding bottom nav from within a screen (e.g., feed camera swipe).
final bottomNavHiddenNotifier = ValueNotifier<bool>(false);

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/feed')) return 0;
    if (location.startsWith('/explore')) return 1;
    // index 2 is services button (no route mapping — handled separately)
    if (location.startsWith('/services')) return 2;
    if (location.startsWith('/reels')) return 3;
    if (location.startsWith('/scanner')) return 4;
    if (location.startsWith('/profile')) return 5;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/services', '/reels', '/scanner', '/profile'];
    if (index == 2) {
      context.go('/services');
      return;
    }
    context.go(routes[index]);
  }

  /// Routes where the bottom nav should be hidden (fullscreen experiences).
  bool _shouldHideNav(String location) {
    if (location.startsWith('/chat/') && location != '/chat') return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final hideNavByRoute = _shouldHideNav(location);

    return ValueListenableBuilder<bool>(
      valueListenable: bottomNavHiddenNotifier,
      builder: (context, hiddenByScreen, _) {
        final hideNav = hideNavByRoute || hiddenByScreen;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: child,
          extendBody: true,
          bottomNavigationBar: hideNav
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? SeeUColors.darkBg
                        : SeeUColors.background,
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? SeeUColors.darkLine
                            : SeeUColors.borderSubtle,
                        width: 1,
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
                            icon: _buildNavIcon('home', false),
                            activeIcon: _buildNavIcon('home', true),
                            label: 'Лента',
                            isSelected: currentIndex == 0,
                            onTap: () => _onTap(context, 0),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('search', false),
                            activeIcon: _buildNavIcon('search', true),
                            label: 'Интересное',
                            isSelected: currentIndex == 1,
                            onTap: () => _onTap(context, 1),
                          ),
                          _ServicesPill(
                            isSelected: currentIndex == 2,
                            onTap: () => _onTap(context, 2),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('reels', false),
                            activeIcon: _buildNavIcon('reels', true),
                            label: 'Рилсы',
                            isSelected: currentIndex == 3,
                            onTap: () => _onTap(context, 3),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('radar', false),
                            activeIcon: _buildNavIcon('radar', true),
                            label: 'Сканер',
                            isSelected: currentIndex == 4,
                            onTap: () => _onTap(context, 4),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('user', false),
                            activeIcon: _buildNavIcon('user', true),
                            label: 'Профиль',
                            isSelected: currentIndex == 5,
                            onTap: () => _onTap(context, 5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }


  Widget _buildNavIcon(String name, bool filled) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _NavIconPainter(name: name, filled: filled),
    );
  }
}

// ─── Services pill (center tab) ──────────────────────────────────────────

class _ServicesPill extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _ServicesPill({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.88,
      child: Container(
        width: 46,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8060), Color(0xFFFF5A3C)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66FF5A3C),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: CustomPaint(
            size: Size(20, 20),
            painter: _GridIconPainter(),
          ),
        ),
      ),
    );
  }
}

// ─── Grid icon painter (for services button) ─────────────────────────────

class _GridIconPainter extends CustomPainter {
  const _GridIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final r = s * 0.14;
    final gap = s * 0.08;
    // 2x2 grid of rounded squares
    final cellSize = (s - gap) / 2;
    // Top-left
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, cellSize, cellSize), Radius.circular(r)),
      paint,
    );
    // Top-right
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cellSize + gap, 0, cellSize, cellSize), Radius.circular(r)),
      paint,
    );
    // Bottom-left
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, cellSize + gap, cellSize, cellSize), Radius.circular(r)),
      paint,
    );
    // Bottom-right
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cellSize + gap, cellSize + gap, cellSize, cellSize), Radius.circular(r)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridIconPainter old) => false;
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
              style: TextStyle(
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
    // Color applied externally via ColorFiltered; paint white here so tint works.
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = filled ? 2.0 : 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      // ── Eye icon (SeeU brand mark) ──────────────────────────────────────
      case 'home':
        final cx = s * 0.5;
        final cy = s * 0.5;

        final eyePath = Path();
        eyePath.moveTo(s * 0.08, cy);
        eyePath.quadraticBezierTo(cx, s * 0.2, s * 0.92, cy);
        eyePath.quadraticBezierTo(cx, s * 0.8, s * 0.08, cy);
        eyePath.close();

        if (filled) {
          canvas.drawPath(eyePath, paint..style = PaintingStyle.fill);
          canvas.drawPath(
            eyePath,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
          canvas.drawCircle(
            Offset(cx, cy),
            s * 0.14,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
          canvas.drawCircle(
            Offset(cx + s * 0.065, cy - s * 0.065),
            s * 0.045,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawPath(
            eyePath,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7,
          );
          canvas.drawCircle(
            Offset(cx, cy),
            s * 0.14,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(
            Offset(cx + s * 0.055, cy - s * 0.055),
            s * 0.04,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        }
        break;

      // ── Search icon (circle + handle + sparkle) ─────────────────────────
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

      // ── Radar icon (arcs + center dot + sweep line) ─────────────────────
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

      // ── User icon ─────────────────────────────────────────────────────
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

      // ── Reels icon (film strip with play) ─────────────────────────────
      case 'reels':
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.1, s * 0.8, s * 0.8),
          Radius.circular(s * 0.15),
        );
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        paint.strokeWidth = 1.7;
        canvas.drawRRect(rect, paint);

        // Film perforations (top and bottom)
        final dotPaint = Paint()
          ..color = Colors.white
          ..style = filled ? PaintingStyle.stroke : PaintingStyle.fill;
        dotPaint.strokeWidth = 1.2;
        for (var i = 0; i < 3; i++) {
          final x = s * (0.28 + i * 0.22);
          canvas.drawCircle(Offset(x, s * 0.21), s * 0.035, dotPaint);
          canvas.drawCircle(Offset(x, s * 0.79), s * 0.035, dotPaint);
        }

        // Play triangle in center
        if (!filled) {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.fill);
        } else {
          // Inverted play triangle for filled state
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeJoin = StrokeJoin.round);
        }
        break;

      // ── Video icon (play in rectangle) ─────────────────────────────────
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

      // ── Folder icon ────────────────────────────────────────────────────
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
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) =>
      name != old.name || filled != old.filled;
}
