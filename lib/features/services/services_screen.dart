import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Сервисы',
                style: SeeUTypography.displayL.copyWith(
                  height: 1.0,
                  letterSpacing: -0.64,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    _SboryHeroCard(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/sbory');
                      },
                    ),
                    const SizedBox(height: 14),
                    _ServiceCard(
                      icon: PhosphorIconsBold.filmStrip,
                      label: 'Видеотека',
                      subtitle: 'Длинные видео, влоги, обзоры',
                      gradient: const [Color(0xFFFF5A3C), Color(0xFFFF8060)],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/watch');
                      },
                    ),
                    const SizedBox(height: 14),
                    _ServiceCard(
                      icon: PhosphorIconsBold.musicNotes,
                      label: 'Аудиотека',
                      subtitle: 'Музыка, плейлисты, новинки',
                      gradient: const [Color(0xFFC04CFD), Color(0xFF7B61FF)],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/music');
                      },
                    ),
                    const SizedBox(height: 14),
                    _ServiceCard(
                      icon: PhosphorIconsBold.folderSimple,
                      label: 'Библиотека',
                      subtitle: 'Файлы, документы, материалы',
                      gradient: const [Color(0xFF2FA84F), Color(0xFF1AC8B8)],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/files');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Сборы hero card ─────────────────────────────────────────────

class _SboryHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SboryHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [SeeUColors.accent, SeeUColors.accentSecondary, SeeUColors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.55, 1],
          ),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Stack(
          children: [
            Positioned(
              right: -10, bottom: -20,
              child: Opacity(
                opacity: 0.18,
                child: Icon(
                  PhosphorIconsBold.usersThree,
                  size: 120, color: Colors.white,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.usersThree,
                        color: Colors.white, size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сборы',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Оффлайн и онлайн активности',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        children: [
                          Text(
                            'Смотреть сборы',
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(PhosphorIconsBold.arrowRight, size: 12, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Service card ─────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIconsRegular.caretRight,
              color: Colors.white.withValues(alpha: 0.7),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
