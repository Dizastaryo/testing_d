import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/models/reading.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/reading_provider.dart';
import 'library_design.dart';
import 'readers/open_reader.dart';

/// Читальня — дом библиотеки. Hero «продолжить чтение» как обложка номера,
/// серия и цель года одной строкой, категории-корешки, «читаю сейчас».
class ReadingRoomScreen extends ConsumerWidget {
  const ReadingRoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.seeuColors.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              LibMainBar(
                title: 'Читальня',
                action: LibSquareButton(
                  icon: PhosphorIcons.magnifyingGlass(),
                  onTap: () => context.go('/library/discover'),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: SeeUColors.accent,
                  onRefresh: () async {
                    ref.invalidate(recentlyReadProvider);
                    ref.invalidate(readingListProvider('reading'));
                    ref.invalidate(readingStatsProvider);
                    ref.invalidate(readingGoalProvider);
                    ref.invalidate(fileCategoriesProvider);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        20, 0, 20, 28 + context.bottomBarInset),
                    children: const [
                      _ContinueHero(),
                      SizedBox(height: 18),
                      _StreakGoalStrip(),
                      SizedBox(height: 28),
                      _CategoriesBlock(),
                      SizedBox(height: 28),
                      _ReadingNowBlock(),
                    ],
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

// ─── Hero «вы остановились на» ──────────────────────────────────────────────

class _ContinueHero extends ConsumerWidget {
  const _ContinueHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyReadProvider).valueOrNull ?? const [];
    final reading =
        ref.watch(readingListProvider('reading')).valueOrNull ?? const [];

    // «Вы остановились на» — последняя открытая книга; если истории чтения ещё
    // нет, берём первую из «читаю».
    final file = recent.isNotEmpty
        ? recent.first
        : (reading.isNotEmpty ? reading.first : null);

    if (file == null) return const _EmptyHero();
    return _HeroCard(file: file);
  }
}

class _HeroCard extends ConsumerWidget {
  final FileItem file;
  const _HeroCard({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final progress = ref.watch(readingProgressProvider(file.id)).valueOrNull;
    final pct = progress?.percentage ?? 0;
    // «Страница X из Y» и оценку времени показываем только для постраничных
    // (PDF). У текстовых книг position — пиксельный offset, из которого раньше
    // получалось «страница 0 из 15234» и «осталось ~406 ч».
    final isPageBased = progress?.isPageBased ?? false;
    final page = (progress?.position['page'] as num?)?.toInt() ?? 0;
    final total = isPageBased
        ? ((progress?.position['total'] as num?)?.toInt() ?? 0)
        : (file.pagesCount > 0 ? file.pagesCount : 0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? LibColors.heroDark : LibColors.heroLight,
        ),
        border: dark ? Border.all(color: SeeUColors.darkLine) : null,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B2119).withValues(alpha: dark ? 0.7 : 0.72),
            blurRadius: 60,
            offset: const Offset(0, 34),
            spreadRadius: -24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Тёплое свечение из правого верхнего угла.
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.4),
                    radius: 0.62,
                    colors: [
                      const Color(0xFFFF965F)
                          .withValues(alpha: dark ? 0.24 : 0.32),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookSpine(file: file, width: 118, height: 172, radius: 12),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'вы остановились на',
                          style: SeeUTypography.displayS.copyWith(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: LibColors.heroItalic,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          file.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.displayS.copyWith(
                            fontSize: 25,
                            height: 1.06,
                            letterSpacing: -0.3,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (file.authorName.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            file.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isPageBased && total > 0)
                                    Text(
                                      'страница $page из $total',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.55),
                                      ),
                                    )
                                  else
                                    Text(
                                      '${(pct * 100).toInt()}% прочитано',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  if (isPageBased && total > 0)
                                    Text(
                                      remainingReadingTime(total - page),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SeeUTypography.displayS.copyWith(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text.rich(
                              TextSpan(
                                text: '${(pct * 100).round()}',
                                children: const [
                                  TextSpan(
                                    text: '%',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                              style: SeeUTypography.displayS.copyWith(
                                fontSize: 30,
                                height: 0.8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LibProgressBar(
                          value: pct,
                          track: Colors.white.withValues(alpha: 0.16),
                          gradient: const LinearGradient(
                            colors: [SeeUColors.accent, Color(0xFFFFA070)],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ContinueButton(file: file),
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

class _ContinueButton extends StatelessWidget {
  final FileItem file;
  const _ContinueButton({required this.file});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (canRead(file)) {
          openReader(context, file);
        } else {
          context.push('/files/${file.id}');
        }
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6A4C), SeeUColors.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.7),
              blurRadius: 26,
              offset: const Offset(0, 14),
              spreadRadius: -8,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(PhosphorIconsFill.play, size: 14, color: Colors.white),
            const SizedBox(width: 9),
            Text(
              'Продолжить чтение',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ещё ничего не читали — hero приглашает начать, а не пустует.
class _EmptyHero extends StatelessWidget {
  const _EmptyHero();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? LibColors.heroDark : LibColors.heroLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ещё не начато',
            style: SeeUTypography.displayS.copyWith(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              color: LibColors.heroItalic,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Выберите первую книгу',
            style: SeeUTypography.displayS.copyWith(
              fontSize: 25,
              height: 1.06,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Всё, что откроете, появится здесь — с того места, где остановились.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 18),
          Tappable.scaled(
            onTap: () => context.go('/library/discover'),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF6A4C), SeeUColors.accent],
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Найти книгу',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Серия + цель года ──────────────────────────────────────────────────────

class _StreakGoalStrip extends ConsumerWidget {
  const _StreakGoalStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final goal = ref.watch(readingGoalProvider).valueOrNull;
    final streak = (stats['reading_streak'] as num?)?.toInt() ?? 0;

    return Tappable.scaled(
      onTap: () => context.go('/library/profile'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Row(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Icon(PhosphorIconsFill.flame,
                    size: 18, color: SeeUColors.amber),
                const SizedBox(width: 6),
                Text(
                  '$streak',
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Text('дней',
                    style: TextStyle(fontSize: 11, color: c.ink3)),
              ],
            ),
            Container(
              width: 1,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: LibColors.line(context),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'Цель года · ${goal?.year ?? DateTime.now().year}',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.2,
                          color: c.ink3,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        goal == null
                            ? 'не задана'
                            : '${goal.doneBooks} / ${goal.goalBooks}',
                        style: SeeUTypography.displayS.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LibProgressBar(
                    value: goal?.progress ?? 0,
                    gradient: const LinearGradient(
                      colors: [SeeUColors.accent, SeeUColors.accentSecondary],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(PhosphorIcons.caretRight(), size: 14, color: c.ink4),
          ],
        ),
      ),
    );
  }
}

// ─── Категории — книжные корешки ────────────────────────────────────────────

class _CategoriesBlock extends ConsumerWidget {
  const _CategoriesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fileCategoriesProvider);
    final cats = async.valueOrNull ?? const <FileCategory>[];
    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibSectionHeader(
          title: 'Категории',
          onTap: () => context.go('/library/discover'),
          trailing: Icon(PhosphorIcons.arrowRight(),
              size: 15, color: LibColors.mutedWarm),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < cats.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CategorySpine(cat: cats[i])),
              const SizedBox(width: 13),
              Expanded(
                child: i + 1 < cats.length
                    ? _CategorySpine(cat: cats[i + 1])
                    : const SizedBox(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategorySpine extends StatelessWidget {
  final FileCategory cat;
  const _CategorySpine({required this.cat});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = cat.colorValue;
    // На тёмной теме цифра/иконка светлее — на бумаге, наоборот, глубже.
    final label = dark
        ? Color.lerp(base, Colors.white, 0.28)!
        : Color.lerp(base, Colors.black, 0.22)!;

    return Tappable.scaled(
      onTap: () => context.push('/library/category/${cat.slug}', extra: cat),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LibColors.line(context)),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF1E1914).withValues(alpha: 0.45),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                    spreadRadius: -18,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Корешок книги.
                Container(
                  width: 9,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: LibColors.spineOf(base),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Icon(
                            cat.iconData,
                            size: 26,
                            color: base.withValues(alpha: dark ? 0.34 : 0.24),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 30),
                            Text(
                              cat.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SeeUTypography.displayS.copyWith(
                                fontSize: 18,
                                height: 1.02,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              booksCountLabel(cat.filesCount),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: label,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «128 книг» / «64 книги» / «1 книга».
String booksCountLabel(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return '$n книг';
  if (m10 == 1) return '$n книга';
  if (m10 >= 2 && m10 <= 4) return '$n книги';
  return '$n книг';
}

// ─── Читаю сейчас ───────────────────────────────────────────────────────────

class _ReadingNowBlock extends ConsumerWidget {
  const _ReadingNowBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files =
        ref.watch(readingListProvider('reading')).valueOrNull ?? const [];
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibSectionHeader(
          title: 'Читаю сейчас',
          onTap: () => context.go('/library/shelf'),
          trailing: const LibSectionAction('Все'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(width: 15),
            itemBuilder: (_, i) => _ReadingNowCard(file: files[i]),
          ),
        ),
      ],
    );
  }
}

class _ReadingNowCard extends ConsumerWidget {
  final FileItem file;
  const _ReadingNowCard({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final ReadingProgress? p =
        ref.watch(readingProgressProvider(file.id)).valueOrNull;

    return Tappable.scaled(
      onTap: () {
        if (canRead(file)) {
          openReader(context, file);
        } else {
          context.push('/files/${file.id}');
        }
      },
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookSpine(
              file: file,
              width: 110,
              height: 148,
              progress: (p?.percentage ?? 0) > 0 ? p!.percentage : null,
            ),
            const SizedBox(height: 8),
            Text(
              file.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.22,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
