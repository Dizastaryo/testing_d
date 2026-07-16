import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/nearest_sbor_provider.dart';
import '../music/audio_design.dart';

/// Витрина сервисов (§06 дизайн-ядра): не список из трёх строк, а три двери в
/// разные миры. Каждая карточка носит характер своего сервиса. Порядок
/// фиксированный по приоритету продукта: Сборы (ближе всего к сути — привести
/// людей в одно место офлайн) → Аудиотека → Библиотека.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider).valueOrNull;
    final nearestSbor = ref.watch(nearestSborProvider).valueOrNull;
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Бренд-wordmark + серифный заголовок раздела, как в ленте.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SeeU',
                    style: TextStyle(
                      fontFamily: AppFonts.I.brand,
                      fontSize: 26,
                      height: 1.0,
                      color: SeeUColors.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Сервисы',
                    style: SeeUTypography.displayL.copyWith(
                      height: 1.0,
                      letterSpacing: -0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                children: [
                  _SboryHeroCard(
                    nearest: nearestSbor,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.push('/sbory');
                    },
                  ),
                  const SizedBox(height: 14),
                  _AudioServiceCard(
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
    );
  }
}

// ─── Сборы hero card ─────────────────────────────────────────────

class _SboryHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  final Sbor? nearest;
  const _SboryHeroCard({required this.onTap, this.nearest});

  /// Живая строка: «когда · место · N идут» ближайшего сбора. Пусто → CTA.
  String? _liveLine() {
    final s = nearest;
    if (s == null) return null;
    final parts = <String>[];
    if (s.when.isNotEmpty) parts.add(s.when);
    if (s.place.isNotEmpty) parts.add(s.place);
    if (s.joined > 0) parts.add('${s.joined} идут');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveLine();
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              SeeUColors.accent,
              SeeUColors.accentSecondary,
              SeeUColors.amber
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.55, 1],
          ),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        // Клип по радиусу самой карточки: фоновая иконка отсчитывается от
        // края карточки (right:-14 / bottom:-20), а не от паддинга контента.
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned(
              right: -14,
              bottom: -20,
              child: Opacity(
                opacity: 0.16,
                child: Icon(
                  PhosphorIconsFill.usersThree,
                  size: 130,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.usersThree,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сборы',
                          // Спека §06: 700 18 белый.
                          style: SeeUTypography.title.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Встречи людей рядом',
                          // Спека §06: 500 12 rgba(255,255,255,.8).
                          style: SeeUTypography.caption.copyWith(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Живой pill: ближайший сбор (время · место · сколько идут).
                // Пока впереди пусто — обычный CTA «Смотреть сборы».
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: live != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                live,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SeeUTypography.caption.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Смотреть сборы',
                              style: SeeUTypography.caption.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(PhosphorIconsBold.arrowRight,
                                size: 12, color: Colors.white),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Аудиотека — тёмная сливовая дверь ─────────────────────────────

class _AudioServiceCard extends ConsumerWidget {
  final VoidCallback onTap;
  const _AudioServiceCard({required this.onTap});

  /// Светлый фиолетовый под тёмную сливовую карточку — для эквалайзера и
  /// иконки паузы live-строки (чистый plum на #241033 читается слабо).
  static const Color _liveAccent = Color(0xFFD9B8FF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // «Живая» карточка: если в плеере есть трек — вместо статичной подписи
    // показываем «что играет» с эквалайзером (на паузе — иконка паузы).
    final track = ref.watch(miniPlayerProvider.select((s) => s.track));
    final playing = ref.watch(miniPlayerProvider.select((s) => s.playing));
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF241033), Color(0xFF3D1A5C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          // В тёмной теме карточка почти сливается с фоном — тонкий контур.
          border: c.isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SeeUColors.plum, SeeUColors.info],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(PhosphorIconsFill.musicNotes,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Аудиотека',
                    // Спека §06: 700 17 белый.
                    style: SeeUTypography.title.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (track == null)
                    Text(
                      'Звуки, музыка и голоса',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    )
                  else
                    Row(
                      children: [
                        if (playing)
                          const NowPlayingBars(color: _liveAccent, height: 12)
                        else
                          const Icon(PhosphorIconsFill.pause,
                              size: 11, color: _liveAccent),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            track.artist.isEmpty
                                ? track.title
                                : '${track.title} · ${track.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.caption.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Icon(
              PhosphorIconsRegular.caretRight,
              color: Colors.white.withValues(alpha: 0.5),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Библиотека — тёплая бумажная дверь со статистикой чтения ───────

class _LibraryServiceCard extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final VoidCallback onTap;

  const _LibraryServiceCard({required this.stats, required this.onTap});

  // Палитра библиотечного мира (тёплая бумага), как в library_design.
  static const Color _paper = Color(0xFFF3ECE0);
  static const Color _paperLine = Color(0xFFE4D8C6);
  static const Color _spineTop = Color(0xFFA0562E);
  static const Color _spineBottom = Color(0xFF7A3F1E);
  static const Color _ink = Color(0xFF3A2A1E);
  static const Color _inkMuted = Color(0xFF6A5A48);

  @override
  Widget build(BuildContext context) {
    final done = stats?['books_done'] as int? ?? 0;
    final reading = stats?['books_reading'] as int? ?? 0;
    final streak = stats?['reading_streak'] as int? ?? 0;
    final hasStats = done + reading > 0;

    // Тёмная тема: «бумага» уступает тёмной поверхности, но характер
    // (корешок-градиент, сериф, тёплые оттенки) сохраняется.
    final c = context.seeuColors;
    final paper = c.isDark ? SeeUColors.darkSurface : _paper;
    final line = c.isDark ? SeeUColors.darkLine : _paperLine;
    final ink = c.isDark ? SeeUColors.darkInk : _ink;
    final inkMuted = c.isDark ? SeeUColors.darkInk3 : _inkMuted;
    final caret = c.isDark ? SeeUColors.darkInk4 : const Color(0xFFB0A08C);
    // #B0442A на тёмной поверхности не читается — берём светлый коралл.
    final streakInk =
        c.isDark ? SeeUColors.accentSecondary : const Color(0xFFB0442A);

    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 104, // Спека §06: Библиотека — 104, как Аудиотека.
        decoration: BoxDecoration(
          color: paper,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(SeeURadii.card),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_spineTop, _spineBottom],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _spineBottom.withValues(alpha: 0.25),
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: const Icon(PhosphorIconsFill.books,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Библиотека',
                    style: SeeUTypography.title.copyWith(
                      fontFamily: AppFonts.I.serif,
                      fontSize: 18,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Статы и streak-пилюля в одну строку — карточка
                  // фиксированной высоты 104 не растёт от серии чтения.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hasStats
                              ? '$reading читаю · $done прочитано'
                              : 'Книги, документы, чтение',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Спека §06: 500 12 #6A5A48.
                          style: SeeUTypography.caption.copyWith(
                            fontSize: 12,
                            color: inkMuted,
                          ),
                        ),
                      ),
                      if (streak > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: SeeUColors.accent
                                .withValues(alpha: c.isDark ? 0.18 : 0.12),
                            borderRadius:
                                BorderRadius.circular(SeeURadii.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsFill.flame,
                                  size: 11, color: SeeUColors.accent),
                              const SizedBox(width: 5),
                              Text(
                                '$streak ${_pluralDays(streak)} подряд',
                                // Спека §06: 600 10 #B0442A.
                                style: SeeUTypography.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: streakInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIconsRegular.caretRight,
              color: caret,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) {
      return 'день';
    }
    if (n % 10 >= 2 &&
        n % 10 <= 4 &&
        (n % 100 < 10 || n % 100 >= 20)) {
      return 'дня';
    }
    return 'дней';
  }
}
