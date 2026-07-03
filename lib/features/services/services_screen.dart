import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/library_provider.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider).valueOrNull;
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SeeUSectionHeader(
                kicker: 'SEEU · РАЗДЕЛЫ',
                title: 'Сервисы',
                hairline: true,
                padding: EdgeInsets.zero,
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
                      icon: PhosphorIconsBold.musicNotes,
                      label: 'Аудиотека',
                      subtitle: 'Музыка, плейлисты, новинки',
                      gradient: const [SeeUColors.plum, SeeUColors.info],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/music');
                      },
                    ),
                    const SizedBox(height: 14),
                    _LibraryServiceCard(
                      stats: stats,
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
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.usersThree,
                        color: Colors.white, size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сборы',
                          style: SeeUTypography.title
                              .copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Оффлайн и онлайн активности',
                          style: SeeUTypography.caption
                              .copyWith(color: Colors.white70),
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
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Смотреть сборы',
                            style: SeeUTypography.caption.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(PhosphorIconsBold.arrowRight,
                              size: 12, color: Colors.white),
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
                borderRadius: BorderRadius.circular(SeeURadii.medium),
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
                    style: SeeUTypography.title.copyWith(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: SeeUTypography.caption.copyWith(
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

// ─── Library card with reading stats ──────────────────────────────────────────

class _LibraryServiceCard extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final VoidCallback onTap;

  const _LibraryServiceCard({required this.stats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = stats?['books_done'] as int? ?? 0;
    final reading = stats?['books_reading'] as int? ?? 0;
    final streak = stats?['reading_streak'] as int? ?? 0;
    final hasStats = done + reading > 0;

    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [SeeUColors.success, SeeUColors.info],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.success.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                  ),
                  child: const Icon(PhosphorIconsBold.books,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Библиотека',
                        style: SeeUTypography.title.copyWith(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasStats
                            ? '$reading читаю · $done прочитано'
                            : 'Книги, документы, чтение',
                        style: SeeUTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
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
            if (streak > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsFill.flame,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      '$streak ${_pluralDays(streak)} подряд',
                      style: SeeUTypography.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) { return 'день'; }
    if (n % 10 >= 2 && n % 10 <= 4 &&
        (n % 100 < 10 || n % 100 >= 20)) { return 'дня'; }
    return 'дней';
  }
}
