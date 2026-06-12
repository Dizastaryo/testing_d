import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';

class _LeaderboardEntry {
  final int rank;
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final int totalLikes;

  const _LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.totalLikes,
  });

  factory _LeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      _LeaderboardEntry(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        totalLikes: (j['total_likes'] as num?)?.toInt() ?? 0,
      );
}

final _leaderboardProvider =
    FutureProvider.autoDispose<List<_LeaderboardEntry>>((ref) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.leaderboard,
      queryParameters: {'limit': '50'});
  final data = r.data is Map ? r.data['data'] ?? r.data : r.data;
  final items = (data is Map ? data['items'] : data) as List? ?? [];
  return items
      .map((e) => _LeaderboardEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(_leaderboardProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Топ по лайкам',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: c.ink,
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: SeeUColors.accent)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill),
                  size: 48, color: SeeUColors.error),
              const SizedBox(height: 12),
              Text('Не удалось загрузить', style: TextStyle(color: c.ink2)),
              const SizedBox(height: 12),
              SeeUButton(
                  label: 'Повторить',
                  onTap: () => ref.invalidate(_leaderboardProvider)),
            ],
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.trophy,
                      size: 48, color: c.ink4),
                  const SizedBox(height: 12),
                  Text('В твоём городе пока никого нет',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink2)),
                  const SizedBox(height: 6),
                  Text('Появись в сканере и набери первые лайки!',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (_, i) => _LeaderboardTile(entry: entries[i]),
          );
        },
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final _LeaderboardEntry entry;
  const _LeaderboardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isTop3 = entry.rank <= 3;
    final rankColor = switch (entry.rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => c.ink3,
    };

    return InkWell(
      onTap: () => context.push('/profile/${entry.username}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '#${entry.rank}',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: isTop3 ? 16 : 13,
                  fontWeight: isTop3 ? FontWeight.w800 : FontWeight.w500,
                  color: rankColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 22,
              backgroundColor: c.surface2,
              backgroundImage: entry.avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(entry.avatarUrl)
                  : null,
              child: entry.avatarUrl.isEmpty
                  ? Text(
                      entry.username.isNotEmpty
                          ? entry.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.username,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: c.ink)),
                  if (entry.fullName.isNotEmpty)
                    Text(entry.fullName,
                        style: TextStyle(fontSize: 12, color: c.ink3)),
                ],
              ),
            ),
            Row(
              children: [
                Icon(PhosphorIconsFill.heart,
                    color: SeeUColors.accent, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${entry.totalLikes}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
