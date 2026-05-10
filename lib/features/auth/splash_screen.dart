import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Ключ в SharedPreferences. Если флаг != true — splash перенаправит
/// неавторизованного юзера на /onboarding перед /login.
const _onboardingSeenKey = 'onboarding_seen_v1';

/// Cinematic splash. Расходящийся оранжевый круг от центра + растущий
/// логотип «SeeU». После 1200ms перенаправляет: на `/feed` если юзер
/// уже авторизован, иначе на `/login`. Если auth-check ещё крутится —
/// ждёт его завершения.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _navigated = false;
  bool? _onboardingSeen; // null = ещё не прочитан флаг

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _maybeNavigate();
    });
    _loadOnboardingFlag();
  }

  Future<void> _loadOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false);
    // Если анимация уже отработала к моменту прихода флага — навигируем сразу.
    if (_ctrl.isCompleted) _maybeNavigate();
  }

  void _maybeNavigate() {
    if (_navigated) return;
    final auth = ref.read(authProvider);
    if (auth.isLoading) return; // дождёмся следующего ребилда
    if (_onboardingSeen == null) return; // ждём prefs
    _navigated = true;
    String dest;
    if (auth.isAuthenticated) {
      dest = '/feed';
    } else if (!_onboardingSeen!) {
      dest = '/onboarding';
    } else {
      dest = '/login';
    }
    if (mounted) context.go(dest);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Если auth уже settled и анимация завершилась — повторно дёрнем navigate.
    ref.listen(authProvider, (_, __) {
      if (_ctrl.isCompleted) _maybeNavigate();
    });

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          // Easing: круг расходится с overshoot, логотип появляется чуть позже
          final ringT = Curves.easeOutCubic.transform(t);
          final logoT = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
          final logoScale =
              0.85 + 0.15 * Curves.easeOutBack.transform(logoT);
          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Расходящееся оранжевое кольцо (как пульс радара)
                _Ring(progress: ringT, base: 0.0, width: 90),
                _Ring(progress: ringT, base: 0.18, width: 70),
                _Ring(progress: ringT, base: 0.36, width: 50),
                // Центральный логотип
                Opacity(
                  opacity: logoT,
                  child: Transform.scale(
                    scale: logoScale,
                    child: ShaderMask(
                      shaderCallback: (rect) =>
                          SeeUGradients.heroOrange.createShader(rect),
                      child: const Text(
                        'SeeU',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 64,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -2,
                          color: Colors.white,
                        ),
                      ),
                    ),
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

class _Ring extends StatelessWidget {
  final double progress; // 0..1
  final double base; // фаза 0..1
  final double width;

  const _Ring({
    required this.progress,
    required this.base,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final local = ((progress - base) / (1.0 - base)).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();
    final size = width + 280 * local;
    final opacity = (1.0 - local) * 0.6;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: opacity),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

