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
    if (location.startsWith('/scanner')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/scanner', '/notifications', '/profile'];
    context.go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      extendBody: true,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: SeeUColors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              boxShadow: SeeUShadows.md,
              border: Border.all(
                color: SeeUColors.borderSubtle,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: _buildNavIcon('home', false),
                  activeIcon: _buildNavIcon('home', true),
                  isSelected: currentIndex == 0,
                  onTap: () => _onTap(context, 0),
                ),
                _NavItem(
                  icon: _buildNavIcon('search', false),
                  activeIcon: _buildNavIcon('search', true),
                  isSelected: currentIndex == 1,
                  onTap: () => _onTap(context, 1),
                ),
                _ScannerFab(
                  isSelected: currentIndex == 2,
                  onTap: () => _onTap(context, 2),
                ),
                _NavItem(
                  icon: _buildNavIcon('heart', false),
                  activeIcon: _buildNavIcon('heart', true),
                  isSelected: currentIndex == 3,
                  onTap: () => _onTap(context, 3),
                ),
                _NavItem(
                  icon: _buildNavIcon('user', false),
                  activeIcon: _buildNavIcon('user', true),
                  isSelected: currentIndex == 4,
                  onTap: () => _onTap(context, 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon(String name, bool filled) {
    // Custom SVG-style icons using paths matching the design
    return CustomPaint(
      size: const Size(22, 22),
      painter: _NavIconPainter(name: name, filled: filled),
    );
  }
}

// ─── Scanner FAB (center tab) ────────────────────────────────────────────

class _ScannerFab extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _ScannerFab({required this.isSelected, required this.onTap});

  @override
  State<_ScannerFab> createState() => _ScannerFabState();
}

class _ScannerFabState extends State<_ScannerFab>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOut));

    if (widget.isSelected) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(covariant _ScannerFab old) {
    super.didUpdateWidget(old);
    if (widget.isSelected && !old.isSelected) {
      _pulseController.repeat();
      _bounceController.forward(from: 0);
    } else if (!widget.isSelected && old.isSelected) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.88,
      child: AnimatedBuilder(
        animation: _bounceAnim,
        builder: (_, child) => Transform.scale(
          scale: widget.isSelected ? _bounceAnim.value : 1.0,
          child: child,
        ),
        child: SizedBox(
          width: 56,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Radar pulse rings
              if (widget.isSelected)
                ...List.generate(2, (i) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      final delay = i * 0.3;
                      final t = (_pulseController.value + delay) % 1.0;
                      final scale = 0.6 + t * 1.6;
                      final opacity = (1.0 - t) * 0.7;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: SeeUColors.accent.withValues(alpha: opacity),
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              // Main button
              Positioned(
                top: -6,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.isSelected
                        ? const RadialGradient(
                            center: Alignment(-0.3, -0.3),
                            colors: [
                              Color(0xFFFF8060),
                              Color(0xFFFF5A3C),
                              Color(0xFFE04020),
                            ],
                            stops: [0.0, 0.6, 1.0],
                          )
                        : null,
                    color: widget.isSelected ? null : SeeUColors.surface2,
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: SeeUColors.accent.withValues(alpha: 0.5),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: SeeUColors.accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _EyeIcon(
                      size: 24,
                      color: widget.isSelected ? Colors.white : SeeUColors.textTertiary,
                      filled: widget.isSelected,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Eye icon widget ─────────────────────────────────────────────────────

class _EyeIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool filled;

  const _EyeIcon({required this.size, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _EyeIconPainter(color: color, filled: filled),
    );
  }
}

class _EyeIconPainter extends CustomPainter {
  final Color color;
  final bool filled;

  _EyeIconPainter({required this.color, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    // Eye shape
    final eyePath = Path();
    eyePath.moveTo(s * 0.083, s / 2);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.1, s / 2, s * 0.1);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.1, s * 0.917, s / 2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.9, s / 2, s * 0.9);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.9, s * 0.083, s / 2);
    eyePath.close();

    if (filled) {
      canvas.drawPath(eyePath, Paint()..color = color);
      // White eye interior
      canvas.drawCircle(
        center,
        s * 0.2,
        Paint()..color = Colors.white,
      );
      // Pupil
      canvas.drawCircle(
        center,
        s * 0.1,
        Paint()..color = color,
      );
    } else {
      canvas.drawPath(
        eyePath,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      canvas.drawCircle(
        center,
        s * 0.13,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EyeIconPainter old) =>
      color != old.color || filled != old.filled;
}

// ─── Nav item ────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final Widget icon;
  final Widget activeIcon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
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
    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.85,
      child: SizedBox(
        width: 44,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _bounceAnimation,
              builder: (context, child) {
                final scale =
                    widget.isSelected ? _bounceAnimation.value : 1.0;
                final effectiveScale = widget.isSelected &&
                        !_bounceController.isAnimating
                    ? 1.1
                    : scale;
                return Transform.scale(
                  scale: effectiveScale,
                  child: child,
                );
              },
              child: widget.isSelected ? widget.activeIcon : widget.icon,
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
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
    final color = filled ? SeeUColors.textPrimary : SeeUColors.textTertiary;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
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
        canvas.drawPath(path, paint..style = filled ? PaintingStyle.fill : PaintingStyle.stroke);
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
          paint..style = PaintingStyle.stroke..strokeWidth = filled ? 2.5 : 1.8,
        );
        break;

      case 'heart':
        final path = Path();
        path.moveTo(s * 0.5, s * 0.85);
        path.cubicTo(s * 0.2, s * 0.65, s * 0.08, s * 0.45, s * 0.08, s * 0.35);
        path.cubicTo(s * 0.08, s * 0.18, s * 0.22, s * 0.08, s * 0.35, s * 0.08);
        path.cubicTo(s * 0.43, s * 0.08, s * 0.48, s * 0.14, s * 0.5, s * 0.2);
        path.cubicTo(s * 0.52, s * 0.14, s * 0.57, s * 0.08, s * 0.65, s * 0.08);
        path.cubicTo(s * 0.78, s * 0.08, s * 0.92, s * 0.18, s * 0.92, s * 0.35);
        path.cubicTo(s * 0.92, s * 0.45, s * 0.8, s * 0.65, s * 0.5, s * 0.85);
        path.close();
        canvas.drawPath(path, paint..style = filled ? PaintingStyle.fill : PaintingStyle.stroke);
        break;

      case 'user':
        canvas.drawCircle(
          Offset(s * 0.5, s * 0.33),
          s * 0.17,
          paint..style = filled ? PaintingStyle.fill : PaintingStyle.stroke,
        );
        final bodyPath = Path();
        bodyPath.moveTo(s * 0.17, s * 0.875);
        bodyPath.cubicTo(s * 0.17, s * 0.55, s * 0.32, s * 0.54, s * 0.5, s * 0.54);
        bodyPath.cubicTo(s * 0.68, s * 0.54, s * 0.83, s * 0.55, s * 0.83, s * 0.875);
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
