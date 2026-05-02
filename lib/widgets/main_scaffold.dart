import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/design/tokens.dart';
import '../core/design/tappable.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/feed')) return 0;
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/reels')) return 2;
    if (location.startsWith('/scanner')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/reels', '/scanner', '/profile'];
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0x00000000)
              : SeeUColors.surface.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? const Color(0x0FFFFFFF)
                  : SeeUColors.borderSubtle,
              width: 1,
            ),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: _blurFilter,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                    _CreatePill(onTap: () => _onTap(context, 2)),
                    _NavItem(
                      icon: _buildNavIcon('radar', false),
                      activeIcon: _buildNavIcon('radar', true),
                      label: 'Рядом',
                      isSelected: currentIndex == 3,
                      onTap: () => _onTap(context, 3),
                    ),
                    _NavItem(
                      icon: _buildNavIcon('user', false),
                      activeIcon: _buildNavIcon('user', true),
                      label: 'Я',
                      isSelected: currentIndex == 4,
                      onTap: () => _onTap(context, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static final _blurFilter = ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20);

  Widget _buildNavIcon(String name, bool filled) {
    return CustomPaint(
      size: const Size(24, 24),
      painter: _NavIconPainter(name: name, filled: filled),
    );
  }
}

// ─── Create pill (center tab) ─────────────────────────────────────────────

class _CreatePill extends StatelessWidget {
  final VoidCallback onTap;

  const _CreatePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.88,
      child: Container(
        width: 48,
        height: 36,
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
            size: Size(22, 22),
            painter: _PlusIconPainter(),
          ),
        ),
      ),
    );
  }
}

// ─── Plus icon painter ────────────────────────────────────────────────────

class _PlusIconPainter extends CustomPainter {
  const _PlusIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    // Horizontal bar
    canvas.drawLine(Offset(s * 0.2, s * 0.5), Offset(s * 0.8, s * 0.5), paint);
    // Vertical bar
    canvas.drawLine(Offset(s * 0.5, s * 0.2), Offset(s * 0.5, s * 0.8), paint);
  }

  @override
  bool shouldRepaint(covariant _PlusIconPainter old) => false;
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
    final activeColor = isDark ? Colors.white : SeeUColors.textPrimary;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : SeeUColors.textTertiary;

    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.85,
      child: SizedBox(
        width: 56,
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
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                color: widget.isSelected ? activeColor : inactiveColor,
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
      ..strokeWidth = filled ? 2.0 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      case 'home':
        final path = Path();
        path.moveTo(s * 0.125, s * 0.458);
        path.lineTo(s * 0.5, s * 0.125);
        path.lineTo(s * 0.875, s * 0.458);
        path.lineTo(s * 0.875, s * 0.833);
        path.quadraticBezierTo(s * 0.875, s * 0.917, s * 0.792, s * 0.917);
        path.lineTo(s * 0.625, s * 0.917);
        path.lineTo(s * 0.625, s * 0.625);
        path.lineTo(s * 0.375, s * 0.625);
        path.lineTo(s * 0.375, s * 0.917);
        path.lineTo(s * 0.208, s * 0.917);
        path.quadraticBezierTo(s * 0.125, s * 0.917, s * 0.125, s * 0.833);
        path.close();
        canvas.drawPath(
            path,
            paint
              ..style =
                  filled ? PaintingStyle.fill : PaintingStyle.stroke);
        break;

      case 'search':
        canvas.drawCircle(
          Offset(s * 0.44, s * 0.44),
          s * 0.3,
          paint..style = PaintingStyle.stroke,
        );
        canvas.drawLine(
          Offset(s * 0.67, s * 0.67),
          Offset(s * 0.88, s * 0.88),
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.5 : 1.6,
        );
        break;

      case 'radar':
        // Concentric arcs suggesting radar / nearby
        final center = Offset(s * 0.5, s * 0.5);
        final arcPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = filled ? 2.0 : 1.6
          ..strokeCap = StrokeCap.round;
        // Outer arc
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.38),
          -2.4, 4.8, false, arcPaint,
        );
        // Middle arc
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.24),
          -2.4, 4.8, false, arcPaint,
        );
        // Center dot
        canvas.drawCircle(center, s * 0.07,
            Paint()..color = Colors.white);
        break;

      case 'user':
        canvas.drawCircle(
          Offset(s * 0.5, s * 0.33),
          s * 0.17,
          paint
            ..style =
                filled ? PaintingStyle.fill : PaintingStyle.stroke,
        );
        final bodyPath = Path();
        bodyPath.moveTo(s * 0.17, s * 0.875);
        bodyPath.cubicTo(
            s * 0.17, s * 0.55, s * 0.32, s * 0.54, s * 0.5, s * 0.54);
        bodyPath.cubicTo(
            s * 0.68, s * 0.54, s * 0.83, s * 0.55, s * 0.83, s * 0.875);
        if (filled) {
          bodyPath.close();
          canvas.drawPath(bodyPath, paint..style = PaintingStyle.fill);
        } else {
          canvas.drawPath(bodyPath, paint..style = PaintingStyle.stroke);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) =>
      name != old.name || filled != old.filled;
}
