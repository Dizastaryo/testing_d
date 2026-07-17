import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/reading_provider.dart';
import 'library_design.dart';

/// Профиль библиотеки — я как читатель: статистика, цель года, серия чтения,
/// место в топе и достижения. Мои книги, коллекции и закладки живут на
/// «Полке» — здесь их не дублируем.
class LibraryProfileScreen extends ConsumerWidget {
  const LibraryProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LibMainBar(title: 'Профиль'),
              Expanded(
                child: RefreshIndicator(
                  color: SeeUColors.accent,
                  onRefresh: () async {
                    ref.invalidate(readingStatsProvider);
                    ref.invalidate(readingGoalProvider);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        20, 6, 20, 28 + context.bottomBarInset),
                    children: const [
                      _Identity(),
                      SizedBox(height: 22),
                      _StatsSection(),
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

// ─── Кто я ──────────────────────────────────────────────────────────────────

class _Identity extends ConsumerWidget {
  const _Identity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final name = (user?.fullName.isNotEmpty ?? false)
        ? user!.fullName
        : (user?.username ?? '');
    final avatar = user?.avatarUrl ?? '';
    final since = user?.createdAt.year;

    return Row(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeeUColors.accentSecondary, SeeUColors.plum],
            ),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.plum.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipOval(
            child: avatar.isNotEmpty
                ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                      style: SeeUTypography.displayS.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeeUTypography.displayS.copyWith(
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (user != null) '@${user.username}',
                  if (since != null) 'читатель с $since',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Секция статистики: единый скелет/ошибка вместо фейковых нулей ───────────

/// Вся сводка читателя грузится из двух источников (статистика + цель года).
/// Пока они грузятся — один скелет; при ошибке — одна кнопка «Повторить».
/// Дочерние блоки строятся только на готовых данных, поэтому нигде не мелькают
/// «0 книг / 0 ч / место —».
class _StatsSection extends ConsumerWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(readingStatsProvider);
    final goalAsync = ref.watch(readingGoalProvider);

    // Есть данные из обоих источников (в т.ч. пока идёт фоновое обновление) —
    // показываем сводку. Иначе: скелет при загрузке, ошибку — если упало и
    // прежних данных ещё нет.
    final hasData = statsAsync.hasValue && goalAsync.hasValue;
    if (!hasData) {
      if (statsAsync.hasError || goalAsync.hasError) {
        return _StatsError(
          onRetry: () {
            ref.invalidate(readingStatsProvider);
            ref.invalidate(readingGoalProvider);
          },
        );
      }
      return const _StatsSkeleton();
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsStrip(),
        SizedBox(height: 18),
        _GoalCard(),
        SizedBox(height: 20),
        _StreakWeek(),
        SizedBox(height: 12),
        _LeaderboardRow(),
        SizedBox(height: 18),
        _Achievements(),
      ],
    );
  }
}

/// Скелет сводки: полоса из четырёх чисел, карточка цели и две карточки ниже.
class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SeeUShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                4,
                (_) => const Column(
                  children: [
                    ShimmerBox(width: 44, height: 30, radius: 8),
                    SizedBox(height: 10),
                    ShimmerBox(width: 40, height: 9, radius: 4),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const ShimmerBox(width: double.infinity, height: 98, radius: 20),
          const SizedBox(height: 20),
          const ShimmerBox(width: double.infinity, height: 96, radius: 18),
          const SizedBox(height: 12),
          const ShimmerBox(width: double.infinity, height: 70, radius: 18),
        ],
      ),
    );
  }
}

/// Компактная ошибка сводки — не показываем нули, если статистика не пришла.
class _StatsError extends StatelessWidget {
  final VoidCallback onRetry;
  const _StatsError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LibColors.line(context)),
      ),
      child: Column(
        children: [
          Icon(PhosphorIcons.cloudWarning(), size: 32, color: c.ink3),
          const SizedBox(height: 10),
          Text(
            'Статистика не загрузилась',
            style: TextStyle(fontSize: 14, color: c.ink2),
          ),
          const SizedBox(height: 14),
          Tappable.scaled(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: LibColors.line(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.arrowClockwise(),
                      size: 14, color: SeeUColors.accent),
                  const SizedBox(width: 7),
                  const Text(
                    'Повторить',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: SeeUColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Статистика: 4 колонки на линейках ──────────────────────────────────────

class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final books = (stats['books_done'] as num?)?.toInt() ?? 0;
    final pages = (stats['total_pages_read'] as num?)?.toInt() ?? 0;
    final seconds = (stats['total_seconds_read'] as num?)?.toInt() ?? 0;
    final streak = (stats['reading_streak'] as num?)?.toInt() ?? 0;
    final hours = seconds ~/ 3600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: LibColors.line(context)),
          bottom: BorderSide(color: LibColors.line(context)),
        ),
      ),
      child: Row(
        children: [
          _stat(context, _compact(books), '', 'книг'),
          _divider(context),
          _stat(context, _compact(pages), _suffix(pages), 'страниц'),
          _divider(context),
          _stat(context, '$hours', 'ч', 'чтения'),
          _divider(context),
          _stat(context, '$streak', '', 'дней', accent: true),
        ],
      ),
    );
  }

  /// 6400 → «6,4» + суффикс «к»; до тысячи — как есть.
  static String _compact(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    final s = k.toStringAsFixed(k < 10 ? 1 : 0).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  static String _suffix(int n) => n >= 1000 ? 'к' : '';

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 44,
        color: LibColors.line(context),
      );

  Widget _stat(
    BuildContext context,
    String value,
    String suffix,
    String label, {
    bool accent = false,
  }) {
    final c = context.seeuColors;
    return Expanded(
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              text: value,
              children: [
                if (suffix.isNotEmpty)
                  TextSpan(
                    text: suffix,
                    style: TextStyle(
                      fontSize: 19,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? SeeUColors.darkInk4
                          : LibColors.mutedWarm,
                    ),
                  ),
              ],
            ),
            style: SeeUTypography.displayS.copyWith(
              fontSize: 34,
              height: 1,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
              color: accent ? SeeUColors.accent : c.ink,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Цель года ──────────────────────────────────────────────────────────────

class _GoalCard extends ConsumerWidget {
  const _GoalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final goal = ref.watch(readingGoalProvider).valueOrNull;
    final progress = goal?.progress ?? 0;
    final left = goal == null ? 0 : (goal.goalBooks - goal.doneBooks);

    return Tappable.scaled(
      onTap: () => _editGoal(context, ref, goal?.goalBooks ?? 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? LibColors.heroDark
                : const [Color(0xFF2A201A), Color(0xFF4A382A)],
          ),
          border: dark ? Border.all(color: SeeUColors.darkLine) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.6, -0.8),
                      radius: 0.6,
                      colors: [
                        const Color(0xFFFF8C5A)
                            .withValues(alpha: dark ? 0.18 : 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    _GoalRing(progress: progress),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'цель на ${goal?.year ?? DateTime.now().year}',
                            style: SeeUTypography.displayS.copyWith(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w400,
                              color: LibColors.goalItalic,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            goal == null
                                ? 'Цель не задана'
                                : '${goal.doneBooks} из ${goal.goalBooks} книг',
                            style: SeeUTypography.displayS.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            goal == null
                                ? 'Нажмите, чтобы поставить цель на год'
                                : goal.achieved
                                    ? 'Цель года достигнута — можно поднять планку'
                                    : 'ещё $left до цели',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: dark
                                  ? c.ink3
                                  : Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _editGoal(
      BuildContext context, WidgetRef ref, int current) async {
    var value = current;
    final saved = await showSeeUBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = ctx.seeuColors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Цель на год',
                    style: SeeUTypography.displayS
                        .copyWith(fontSize: 22, color: c.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Сколько книг хотите дочитать в этом году',
                    style: TextStyle(fontSize: 13, color: c.ink3),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(
                        icon: PhosphorIcons.minus(),
                        onTap: () => setSheet(
                            () => value = math.max(1, value - 1)),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '$value',
                          textAlign: TextAlign.center,
                          style: SeeUTypography.displayS.copyWith(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      _StepButton(
                        icon: PhosphorIcons.plus(),
                        onTap: () => setSheet(
                            () => value = math.min(365, value + 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: SeeUButton(
                      label: 'Сохранить',
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved != true) return;
    final dio = ref.read(libraryApiClientProvider);
    try {
      await dio.put(
        ApiEndpoints.myReadingGoal,
        data: {'goal_books': value},
        queryParameters: {'year': DateTime.now().year},
      );
    } catch (_) {
      // Раньше провал сохранения молчал, а UI держал старую цель без сигнала.
      if (context.mounted) {
        showSeeUSnackBar(context, 'Не удалось сохранить цель',
            tone: SeeUTone.danger);
      }
      return;
    }
    ref.invalidate(readingGoalProvider);
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 20, color: c.ink),
      ),
    );
  }
}

/// Кольцо цели: коралловая дуга по проценту, тёмная сердцевина с числом.
class _GoalRing extends StatelessWidget {
  final double progress;
  const _GoalRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(62, 62),
            painter: _RingPainter(progress: progress),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF33261D),
            ),
            alignment: Alignment.center,
            child: Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(
      rect.center,
      size.width / 2,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      true,
      Paint()..color = SeeUColors.accent,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─── Серия чтения по дням недели ────────────────────────────────────────────

class _StreakWeek extends ConsumerWidget {
  const _StreakWeek();

  static const _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final streak = (stats['reading_streak'] as num?)?.toInt() ?? 0;
    final week = ((stats['week_days'] as List?) ?? const [])
        .map((e) => (e as num?)?.toInt() ?? 0)
        .toList();
    // Сегодняшний день недели (ISO: 1 = Пн) — будущие дни ещё не наступили.
    final today = DateTime.now().weekday;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LibColors.line(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Серия чтения',
                style: SeeUTypography.displayS.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const Spacer(),
              const Icon(PhosphorIconsFill.flame,
                  size: 15, color: SeeUColors.amber),
              const SizedBox(width: 5),
              Text(
                '$streak ${_dayWord(streak)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: dark ? SeeUColors.amber : const Color(0xFFB9791F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: _cell(context, i, week, today, dark),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_days[i],
                        style: TextStyle(fontSize: 10, color: c.ink3)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Читал — коралл; сегодня ещё не читал — приглушённый коралл; впереди или
  /// пропущено — пустая ячейка.
  Color _cell(BuildContext context, int i, List<int> week, int today, bool dark) {
    final read = i < week.length && week[i] > 0;
    if (read) return SeeUColors.accent;
    if (i + 1 == today) {
      return dark ? const Color(0xFF7A3322) : const Color(0xFFFFC9BB);
    }
    return LibColors.chip(context);
  }

  static String _dayWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'дней';
    if (m10 == 1) return 'день';
    if (m10 >= 2 && m10 <= 4) return 'дня';
    return 'дней';
  }
}

// ─── Место в топе читателей ─────────────────────────────────────────────────

class _LeaderboardRow extends ConsumerWidget {
  const _LeaderboardRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final rank = (stats['my_rank'] as num?)?.toInt() ?? 0;
    final total = (stats['total_readers'] as num?)?.toInt() ?? 0;

    return Tappable.scaled(
      onTap: () => context.push('/reading/leaderboard'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LibColors.line(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeeUColors.amber.withValues(alpha: dark ? 0.16 : 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                PhosphorIconsFill.trophy,
                size: 20,
                color: dark ? SeeUColors.amber : const Color(0xFFE4B70C),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Топ читателей',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    rank > 0
                        ? TextSpan(
                            text: 'Вы на ',
                            children: [
                              TextSpan(
                                text: '$rank месте',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: LibColors.kicker(context),
                                ),
                              ),
                              TextSpan(text: ' из $total'),
                            ],
                          )
                        : const TextSpan(
                            text: 'Дочитайте книгу, чтобы попасть в рейтинг'),
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
            Icon(PhosphorIcons.caretRight(), size: 15, color: c.ink4),
          ],
        ),
      ),
    );
  }
}

// ─── Достижения ─────────────────────────────────────────────────────────────

/// Достижения считаются из настоящей статистики — ни одного декоративного.
class _Achievements extends ConsumerWidget {
  const _Achievements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final stats = ref.watch(readingStatsProvider).valueOrNull ?? const {};
    final streak = (stats['reading_streak'] as num?)?.toInt() ?? 0;
    final done = (stats['books_done'] as num?)?.toInt() ?? 0;
    final pages = (stats['total_pages_read'] as num?)?.toInt() ?? 0;
    final bookmarks = (stats['total_bookmarks'] as num?)?.toInt() ?? 0;
    final ratings = (stats['total_ratings'] as num?)?.toInt() ?? 0;

    final all = <(IconData, Color, bool, String)>[
      (PhosphorIconsFill.flame, SeeUColors.amber, streak >= 7,
          'Неделя без пропусков'),
      (PhosphorIconsFill.medal, SeeUColors.accent, done >= 5,
          'Пять книг дочитано'),
      (PhosphorIconsFill.bookBookmark, SeeUColors.plum, bookmarks >= 10,
          'Десять закладок'),
      (PhosphorIconsFill.books, SeeUColors.success, done >= 20,
          'Двадцать книг'),
      (PhosphorIconsFill.star, SeeUColors.info, ratings >= 5,
          'Пять оценок'),
      (PhosphorIconsFill.fileText, SeeUColors.like, pages >= 1000,
          'Тысяча страниц'),
    ];

    final unlocked = all.where((a) => a.$3).toList();
    final lockedCount = all.length - unlocked.length;
    final shown = unlocked.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Достижения',
              style: SeeUTypography.displayS.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: LibColors.line(context)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final a in shown) ...[
              Tooltip(
                message: a.$4,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: a.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(a.$1, size: 24, color: a.$2),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (lockedCount > 0) ...[
              Opacity(
                opacity: 0.5,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: LibColors.chip(context),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(PhosphorIcons.lockSimple(),
                      size: 22, color: c.ink3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: 0.5,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: LibColors.chip(context),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$lockedCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.ink3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
