import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';

// Radar pulse animation painter
class _RadarPulsePainter extends CustomPainter {
  final double progress; // 0..1
  final int waveIndex;

  _RadarPulsePainter({required this.progress, required this.waveIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.5 + 30;

    // Each wave starts at a different phase offset
    final phaseOffset = waveIndex * 0.33;
    final t = ((progress + phaseOffset) % 1.0);
    final radius = maxRadius * t;
    final opacity = (1.0 - t) * 0.5;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RadarPulsePainter old) =>
      old.progress != progress || old.waveIndex != waveIndex;
}

class _RadarPulse extends StatefulWidget {
  final int waveIndex;
  final double size;

  const _RadarPulse({required this.waveIndex, required this.size});

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _RadarPulsePainter(
          progress: _ctrl.value,
          waveIndex: widget.waveIndex,
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  static const _coralGradientColors = [Color(0xFFFF8060), Color(0xFFFF5A3C)];

  final List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      tag: 'добро пожаловать',
      title: 'Видеть людей,\nне раскрывая себя',
      body:
          'SeeU — социальная сеть, где ты сначала виден как псевдоним, а имя раскрываешь сам.',
      accentIcon: _SlideIcon.eye,
    ),
    _OnboardingSlide(
      tag: 'фишка',
      title: 'Радар\nрядом с тобой',
      body:
          'Чип ESP32 показывает людей в радиусе 50 метров. Ставь лайки тем, кто понравился — без подписок.',
      accentIcon: _SlideIcon.radar,
    ),
    _OnboardingSlide(
      tag: 'безопасно',
      title: 'Только в\nобщественных местах',
      body:
          'Чип сам выключается, когда ты один — никто не узнает где ты живёшь.',
      accentIcon: _SlideIcon.shield,
    ),
  ];

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go('/login');
    }
  }

  void _skip() {
    context.go('/login');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _slides.length - 1;
    final isFirst = _currentPage == 0;

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Slides (flex 1 = all remaining space above bottom panel)
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  return _buildSlide(_slides[index]);
                },
              ),
            ),
            // Dots + button + skip
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 50),
              child: Column(
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _slides.length; i++) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: i == _currentPage ? 22 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? SeeUColors.accent
                                : SeeUColors.textQuaternary,
                            borderRadius:
                                BorderRadius.circular(SeeURadii.pill),
                          ),
                        ),
                        if (i < _slides.length - 1) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Main button: full width, h=56, borderRadius 16, ink bg, bg text
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: SeeUColors.textPrimary,
                        foregroundColor: SeeUColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _nextPage,
                      child: Text(
                        isLast ? 'Поехали' : 'Дальше',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // "Пропустить" link — only on first slide
                  if (isFirst) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _skip,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Пропустить',
                          style: SeeUTypography.caption.copyWith(
                            color: SeeUColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large icon box 160x160, coral gradient, borderRadius 36, radar pulses
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Radar pulse waves (behind the box)
                for (int i = 0; i < 3; i++)
                  _RadarPulse(waveIndex: i, size: 200),
                // Icon box
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(
                      center: Alignment(-0.4, -0.4),
                      colors: _coralGradientColors,
                    ),
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5A3C).withValues(alpha: 0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Icon(
                    _iconData(slide.accentIcon),
                    size: 72,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          // Tag: mono, coral, uppercase
          Text(
            slide.tag.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 11,
              color: SeeUColors.accent,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Serif title, fontSize 36
          Text(
            slide.title,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 36,
              fontWeight: FontWeight.w400,
              color: SeeUColors.textPrimary,
              height: 1.05,
              letterSpacing: -0.72,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          // Body text
          Text(
            slide.body,
            style: SeeUTypography.body.copyWith(
              color: SeeUColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _iconData(_SlideIcon icon) {
    switch (icon) {
      case _SlideIcon.eye:
        return PhosphorIcons.eye(PhosphorIconsStyle.fill);
      case _SlideIcon.radar:
        return PhosphorIcons.waveform(PhosphorIconsStyle.fill);
      case _SlideIcon.shield:
        return PhosphorIcons.shield(PhosphorIconsStyle.fill);
    }
  }
}

enum _SlideIcon { eye, radar, shield }

class _OnboardingSlide {
  final String tag;
  final String title;
  final String body;
  final _SlideIcon accentIcon;

  const _OnboardingSlide({
    required this.tag,
    required this.title,
    required this.body,
    required this.accentIcon,
  });
}
