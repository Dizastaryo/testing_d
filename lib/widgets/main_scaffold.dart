import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/design/tokens.dart';
import '../core/design/tappable.dart';
import 'full_screen_player.dart';
import 'mini_player.dart';

/// Global notifier for hiding bottom nav from within a screen (e.g., feed camera swipe).
final bottomNavHiddenNotifier = ValueNotifier<bool>(false);

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/feed')) return 0;
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/scanner')) return 2;
    if (location.startsWith('/chat')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/scanner', '/chat', '/profile'];
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
          // UX-7: tab-swipe transitions. AnimatedSwitcher с fade+small slide
          // smooth'ит переключение между bottom-nav-tab'ами (Лента →
          // Сервисы → Сканер). Key = current location чтобы AnimatedSwitcher
          // понимал что child реально сменился.
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.012),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(location),
              child: child,
            ),
          ),
          extendBody: true,
          bottomNavigationBar: hideNav
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Persistent mini-player над bottom-nav. Сам решает показываться
                    // ли (если нет активного трека — рендерит SizedBox.shrink()).
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SeeUMiniPlayer(
                        onTap: () => showFullScreenPlayer(context),
                      ),
                    ),
                    Container(
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
                            label: 'Поиск',
                            isSelected: currentIndex == 1,
                            onTap: () => _onTap(context, 1),
                          ),
                          _ScannerPill(
                            isSelected: currentIndex == 2,
                            onTap: () => _onTap(context, 2),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('chat', false),
                            activeIcon: _buildNavIcon('chat', true),
                            label: 'Чаты',
                            isSelected: currentIndex == 3,
                            onTap: () => _onTap(context, 3),
                          ),
                          _NavItem(
                            icon: _buildNavIcon('user', false),
                            activeIcon: _buildNavIcon('user', true),
                            label: 'Профиль',
                            isSelected: currentIndex == 4,
                            onTap: () => _onTap(context, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                  ],
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
            colors: [Color(0xFFFF8060), Color(0xFFFF5A3C)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5A3C).withValues(alpha: isSelected ? 0.55 : 0.35),
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

    // Two radar arcs
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.38),
      -2.4, 4.8, false, paint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.22),
      -2.4, 4.8, false, paint);

    // Center dot
    canvas.drawCircle(center, s * 0.08,
      Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Sweep line
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

      // ── Chat icon (speech bubble) ──────────────────────────────────────
      case 'chat':
        final bubblePath = Path();
        bubblePath.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.12, s * 0.8, s * 0.6),
          Radius.circular(s * 0.18),
        ));
        // Tail
        bubblePath.moveTo(s * 0.25, s * 0.72);
        bubblePath.lineTo(s * 0.18, s * 0.88);
        bubblePath.lineTo(s * 0.42, s * 0.72);
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        paint.strokeWidth = filled ? 2.0 : 1.7;
        canvas.drawPath(bubblePath, paint);
        if (!filled) {
          // Three dots inside
          final dotY = s * 0.42;
          final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(s * 0.35, dotY), s * 0.04, dotPaint);
          canvas.drawCircle(Offset(s * 0.50, dotY), s * 0.04, dotPaint);
          canvas.drawCircle(Offset(s * 0.65, dotY), s * 0.04, dotPaint);
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
