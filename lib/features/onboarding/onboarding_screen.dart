import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/design.dart';

const _onboardingSeenKey = 'onboarding_seen_v1';

/// 5-экранный onboarding с parallax: фоновый «закатный» градиент со
/// светлячком-радар-импульсом движется в 0.5× скорости PageView, передний
/// слой (иконка + текст) — в 1×. Создаёт ощущение глубины при свайпе.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  late final AnimationController _ambient;
  int _currentPage = 0;

  // 5 слайдов: brand-promise → радар → library → музыка/кино → AI-камера.
  final List<_Slide> _slides = const [
    _Slide(
      tag: 'добро пожаловать',
      title: 'Видеть людей,\nне раскрывая себя',
      body:
          'SeeU — социальная сеть нового типа. Имя ты раскрываешь сам, а до этого ты — псевдоним и оранжевая точка на чужом радаре.',
      icon: PhosphorIconsBold.eye,
    ),
    _Slide(
      tag: 'радар встреч',
      title: 'Кто рядом?\nРадар покажет',
      body:
          'BLE-чип ESP32 ловит людей в радиусе 50 метров. Помашите, оставьте реакцию, начните чат — без обязательной подписки.',
      icon: PhosphorIconsBold.radioButton,
    ),
    _Slide(
      tag: 'общая библиотека',
      title: 'Один контент\nна всех',
      body:
          'Делитесь PDF, наборами кистей, обоями, треками. Скачивайте у других. Файлы, которые живут вместе с сообществом.',
      icon: PhosphorIconsBold.bookOpen,
    ),
    _Slide(
      tag: 'музыка и кино',
      title: 'Звук, который\nне исчезает',
      body:
          'Включите трек в Music — он играет, пока вы листаете ленту. Полнометражные фильмы и блоги — отдельная вкладка.',
      icon: PhosphorIconsBold.musicNotes,
    ),
    _Slide(
      tag: 'AI-камера',
      title: 'Маски по запросу.\nФильтры на ползунках',
      body:
          'Опишите маску текстом — AI её сделает. Тон, контраст и зерно — точно как вам нравится. Камера понимает контекст.',
      icon: PhosphorIconsBold.sparkle,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_currentPage < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: SeeUMotion.slow,
        curve: SeeUMotion.smooth,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    // Сохраняем флаг чтобы splash не перенаправлял повторно при следующем
    // запуске. /onboarding всё ещё достижим вручную через URL для тестов.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isLast = _currentPage == _slides.length - 1;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Parallax-фон (медленный)
          _ParallaxBackground(
            controller: _pageCtrl,
            ambient: _ambient,
            slides: _slides,
          ),
          // Передний слой (быстрый PageView с контентом)
          SafeArea(
            child: Column(
              children: [
                // Skip top-right
                Align(
                  alignment: Alignment.centerRight,
                  child: Tappable(
                    onTap: _finish,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Text(
                        'Пропустить',
                        style: SeeUTypography.caption.copyWith(
                          color: c.ink3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _SlideContent(slide: _slides[i]),
                  ),
                ),
                // Dots
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: SeeUMotion.normal,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active ? SeeUColors.accent : c.line,
                          borderRadius:
                              BorderRadius.circular(SeeURadii.pill),
                        ),
                      );
                    }),
                  ),
                ),
                // Primary CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                  child: Tappable.scaled(
                    onTap: _next,
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: SeeUGradients.heroOrange,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        boxShadow: [
                          BoxShadow(
                            color:
                                SeeUColors.accent.withValues(alpha: 0.30),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isLast ? 'Начать' : 'Дальше',
                          style: SeeUTypography.subtitle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final String tag;
  final String title;
  final String body;
  final IconData icon;
  const _Slide({
    required this.tag,
    required this.title,
    required this.body,
    required this.icon,
  });
}

/// Передний слой PageView — иконка + tag-pill + title + body.
class _SlideContent extends StatelessWidget {
  final _Slide slide;
  const _SlideContent({required this.slide});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // Tag pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                color: SeeUColors.accent.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Text(
              slide.tag.toUpperCase(),
              style: SeeUTypography.kicker.copyWith(
                color: SeeUColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Big icon with brand-gradient backplate
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: SeeUGradients.heroOrange,
              borderRadius: BorderRadius.circular(SeeURadii.card),
              boxShadow: [
                BoxShadow(
                  color: SeeUColors.accent.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(slide.icon, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 36),
          // Title
          Text(
            slide.title,
            style: SeeUTypography.displayL.copyWith(height: 1.05),
          ),
          const SizedBox(height: 16),
          // Body
          Text(
            slide.body,
            style: SeeUTypography.body.copyWith(
              color: c.ink2,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// Background-слой с parallax: декорация слайда смещается медленнее
/// (фактор 0.5×) чем сам PageView. На каждом слайде — крупное светящееся
/// пятно brand-цвета в разных позициях.
class _ParallaxBackground extends StatelessWidget {
  final PageController controller;
  final Animation<double> ambient;
  final List<_Slide> slides;

  const _ParallaxBackground({
    required this.controller,
    required this.ambient,
    required this.slides,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, ambient]),
      builder: (_, __) {
        final width = MediaQuery.of(context).size.width;
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? 0.0)
            : 0.0;
        return Stack(
          children: [
            // Soft moving radial blob — главный «солнечный зайчик»
            for (var i = 0; i < slides.length; i++)
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset((i - page) * width * 0.5, 0),
                  child: _Blob(
                    seed: i,
                    ambient: ambient.value,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  final int seed;
  final double ambient; // 0..1, для мерцания

  const _Blob({required this.seed, required this.ambient});

  @override
  Widget build(BuildContext context) {
    // Расположим blob в разных квадрантах по seed:
    // 0 — top-right, 1 — bottom-left, 2 — middle-right, 3 — top-left, 4 — center
    final positions = const [
      Alignment(0.7, -0.6),
      Alignment(-0.6, 0.6),
      Alignment(0.7, 0.2),
      Alignment(-0.5, -0.5),
      Alignment(0.0, 0.0),
    ];
    final align = positions[seed % positions.length];
    // Немного «дышит» вместе с ambient (0..1)
    final breathe = 0.5 + 0.5 * (1 - (ambient * 2 - 1).abs());
    return Align(
      alignment: align,
      child: Container(
        width: 360,
        height: 360,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              SeeUColors.accent.withValues(alpha: 0.22 + 0.10 * breathe),
              SeeUColors.amber.withValues(alpha: 0.10 + 0.06 * breathe),
              SeeUColors.accent.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}
