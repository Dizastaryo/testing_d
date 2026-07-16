import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/library_provider.dart';
import 'library_design.dart';

final _leaderboardMetricProvider = StateProvider<String>((ref) => 'books');

final _readingLeaderboardProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, metric) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.readingLeaderboard,
        queryParameters: {'metric': metric, 'limit': 50});
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

class ReadingLeaderboardScreen extends ConsumerWidget {
  const ReadingLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final metric = ref.watch(_leaderboardMetricProvider);
    final async = ref.watch(_readingLeaderboardProvider(metric));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LibBackBar(kicker: 'БИБЛИОТЕКА', title: 'Читатели'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    _MetricChip(
                      label: 'По книгам',
                      value: 'books',
                      icon: PhosphorIconsRegular.books,
                      selected: metric == 'books',
                      onTap: () => ref
                          .read(_leaderboardMetricProvider.notifier)
                          .state = 'books',
                    ),
                    const SizedBox(width: 8),
                    _MetricChip(
                      label: 'По страницам',
                      value: 'pages',
                      icon: PhosphorIconsRegular.fileText,
                      selected: metric == 'pages',
                      onTap: () => ref
                          .read(_leaderboardMetricProvider.notifier)
                          .state = 'pages',
                    ),
                    const SizedBox(width: 8),
                    _MetricChip(
                      label: 'По серии',
                      value: 'streak',
                      icon: PhosphorIconsRegular.flame,
                      selected: metric == 'streak',
                      onTap: () => ref
                          .read(_leaderboardMetricProvider.notifier)
                          .state = 'streak',
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildList(context, ref, c, async, metric)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, SeeUThemeColors c,
      AsyncValue<List<Map<String, dynamic>>> async, String metric) {
    return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Ошибка загрузки',
                style: TextStyle(color: c.ink3)),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(PhosphorIconsRegular.trophy,
                        size: 32, color: SeeUColors.accent),
                  ),
                  const SizedBox(height: 20),
                  Text('Пока никто не читает',
                      style: SeeUTypography.displayXS.copyWith(color: c.ink)),
                  const SizedBox(height: 6),
                  Text('Стань первым!',
                      style: TextStyle(fontSize: 13, color: c.ink3)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(_readingLeaderboardProvider(metric)),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: entries.length,
              itemBuilder: (ctx, i) =>
                  _LeaderboardEntry(entry: entries[i], metric: metric),
            ),
          );
        },
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent
              : c.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : c.ink3),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : c.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardEntry extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String metric;

  const _LeaderboardEntry({required this.entry, required this.metric});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final rank = entry['rank'] as int? ?? 0;
    final username = entry['username'] as String? ?? '';
    final fullName = entry['full_name'] as String? ?? '';
    final avatarUrl = entry['avatar_url'] as String? ?? '';
    final booksDone = entry['books_done'] as int? ?? 0;
    final totalPages = entry['total_pages'] as int? ?? 0;
    final streakDays = entry['streak_days'] as int? ?? 0;
    final userId = entry['user_id'] as String? ?? '';

    final isTop3 = rank >= 1 && rank <= 3;
    final medalColors = [
      SeeUColors.medalGold, // gold
      SeeUColors.medalSilver, // silver
      SeeUColors.medalBronze, // bronze
    ];

    return GestureDetector(
      onTap: () => context.push('/profile/$userId'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isTop3
              ? medalColors[rank - 1].withValues(alpha: 0.06)
              : Theme.of(context).cardColor,
          border: Border.all(
            color: isTop3
                ? medalColors[rank - 1].withValues(alpha: 0.3)
                : c.line.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 32,
              child: isTop3
                  ? Text(
                      ['🥇', '🥈', '🥉'][rank - 1],
                      style: const TextStyle(fontSize: 20),
                      textAlign: TextAlign.center,
                    )
                  : Text(
                      '#$rank',
                      style: TextStyle(
                        fontFamily: AppFonts.I.sans,
                        fontSize: 12,
                        color: c.ink4,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 12),

            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: c.surface2,
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? Text(
                      username.isNotEmpty
                          ? username[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName.isNotEmpty ? fullName : username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@$username',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),

            // Score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  metric == 'pages'
                      ? _formatPages(totalPages)
                      : metric == 'streak'
                          ? '$streakDays'
                          : '$booksDone',
                  style: TextStyle(
                    fontFamily: AppFonts.I.sans,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isTop3 ? medalColors[rank - 1] : c.ink,
                  ),
                ),
                Text(
                  metric == 'pages'
                      ? 'стр.'
                      : metric == 'streak'
                          ? _pluralDays(streakDays)
                          : _pluralBooks(booksDone),
                  style: TextStyle(fontSize: 10, color: c.ink3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPages(int pages) {
    if (pages >= 1000) return '${(pages / 1000).toStringAsFixed(1)}K';
    return '$pages';
  }

  String _pluralBooks(int n) {
    final m = n % 10;
    final h = n % 100;
    if (h >= 11 && h <= 19) return 'книг';
    if (m == 1) return 'книга';
    if (m >= 2 && m <= 4) return 'книги';
    return 'книг';
  }

  String _pluralDays(int n) {
    final m = n % 10;
    final h = n % 100;
    if (h >= 11 && h <= 19) return 'дней';
    if (m == 1) return 'день';
    if (m >= 2 && m <= 4) return 'дня';
    return 'дней';
  }
}
