import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/design/design.dart';
import '../../core/models/notification.dart';
import '../../core/providers/notification_provider.dart';

// "Все" vs "Ответы" (replies/comments/mentions) pill toggle
enum _NotifFilter { all, replies }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotifFilter _activeFilter = _NotifFilter.all;

  List<AppNotification> _filtered(List<AppNotification> all) {
    switch (_activeFilter) {
      case _NotifFilter.all:
        return all;
      case _NotifFilter.replies:
        return all
            .where((n) =>
                n.type == NotificationType.comment ||
                n.type == NotificationType.reply ||
                n.type == NotificationType.mention)
            .toList();
    }
  }

  String _filterLabel(_NotifFilter f) {
    switch (f) {
      case _NotifFilter.all:
        return 'Все';
      case _NotifFilter.replies:
        return 'Ответы';
    }
  }

  IconData _notifIcon(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        // heart for like
        return PhosphorIcons.heart(PhosphorIconsStyle.fill);
      case NotificationType.follow:
        // user for follow
        return PhosphorIcons.userPlus(PhosphorIconsStyle.fill);
      case NotificationType.comment:
        // chat for comment
        return PhosphorIcons.chatCircle(PhosphorIconsStyle.fill);
      case NotificationType.reply:
        // chat (reply) — maps to remix concept in design
        return PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.fill);
      case NotificationType.mention:
        // at for mention
        return PhosphorIcons.at(PhosphorIconsStyle.fill);
      case NotificationType.postTag:
        // radar-style for post tag (nearby mapping)
        return PhosphorIcons.tag(PhosphorIconsStyle.fill);
    }
  }

  Color _notifIconColor(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return SeeUColors.like;
      case NotificationType.follow:
        return SeeUColors.accent;
      case NotificationType.comment:
        return const Color(0xFFFFB547);
      case NotificationType.reply:
        return const Color(0xFFC04CFD);
      case NotificationType.mention:
        return const Color(0xFF85B7EB);
      case NotificationType.postTag:
        return SeeUColors.success;
    }
  }

  // Group notifications by time period
  Map<String, List<AppNotification>> _groupByTime(
      List<AppNotification> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));

    final Map<String, List<AppNotification>> groups = {};

    for (final n in notifications) {
      final nDate = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      String key;
      if (nDate.isAtSameMomentAs(today) || nDate.isAfter(today)) {
        key = 'Сегодня';
      } else if (nDate.isAfter(weekAgo)) {
        key = 'На этой неделе';
      } else {
        key = 'Ранее';
      }
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(n);
    }

    // Sort groups in desired order
    final ordered = <String, List<AppNotification>>{};
    for (final label in ['Сегодня', 'На этой неделе', 'Ранее']) {
      if (groups.containsKey(label)) {
        ordered[label] = groups[label]!;
      }
    }
    return ordered;
  }

  void _onNotificationTap(AppNotification n) {
    ref.read(notificationProvider.notifier).markRead(n.id);
    if (n.type == NotificationType.follow) {
      context.push('/profile/${n.fromUser.username}');
    } else if (n.postId != null) {
      context.push('/post/${n.postId}');
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(notificationProvider.notifier).loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final notifState = ref.watch(notificationProvider);
    final filtered = _filtered(notifState.notifications);
    final grouped = _groupByTime(filtered);
    final flatItems = _buildFlatList(grouped);

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: serif "Активность"
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  Text(
                    'Активность',
                    style: SeeUTypography.displayL,
                  ),
                  const Spacer(),
                  if (notifState.unreadCount > 0)
                    GestureDetector(
                      onTap: () => ref.read(notificationProvider.notifier).markAllRead(),
                      child: Text(
                        'Прочитать все',
                        style: SeeUTypography.caption.copyWith(
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // "Все" | "Ответы" pill toggle
            _buildFilterRow(),
            const Divider(height: 1, color: SeeUColors.borderSubtle),
            // Content
            Expanded(
              child: notifState.isLoading
                  ? SeeUShimmer(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: 8,
                        itemBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            height: 72,
                            decoration: BoxDecoration(
                              color: SeeUColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(SeeURadii.small),
                            ),
                          ),
                        ),
                      ),
                    )
                  : filtered.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: SeeUColors.accent,
                      child: AnimationLimiter(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: flatItems.length,
                          itemBuilder: (context, index) =>
                              flatItems[index],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: SeeUColors.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _NotifFilter.values.map((f) {
            final isActive = f == _activeFilter;
            return GestureDetector(
              onTap: () => setState(() => _activeFilter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? SeeUColors.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Text(
                  _filterLabel(f),
                  style: SeeUTypography.caption.copyWith(
                    fontSize: 13,
                    color: isActive ? Colors.white : SeeUColors.textSecondary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Pre-build flat list from grouped structure (P06: avoid O(n^2) in itemBuilder)
  List<Widget> _buildFlatList(Map<String, List<AppNotification>> grouped) {
    final items = <Widget>[];
    int position = 0;
    for (final entry in grouped.entries) {
      items.add(_buildSectionHeader(entry.key));
      position++;
      for (final notif in entry.value) {
        items.add(
          AnimationConfiguration.staggeredList(
            position: position,
            duration: const Duration(milliseconds: 350),
            delay: const Duration(milliseconds: 40),
            child: SlideAnimation(
              verticalOffset: 20,
              curve: Curves.easeOutCubic,
              child: FadeInAnimation(
                curve: Curves.easeOutCubic,
                child: _buildNotificationTile(notif),
              ),
            ),
          ),
        );
        position++;
      }
    }
    return items;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        title,
        style: SeeUTypography.subtitle.copyWith(
          fontWeight: FontWeight.w700,
          color: SeeUColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildNotificationTile(AppNotification n) {
    return GestureDetector(
      onTap: () => _onNotificationTap(n),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: n.isRead
              ? Colors.transparent
              : SeeUColors.accentSoft.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Row(
          children: [
            // Avatar with type icon badge
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: SeeUColors.surfaceElevated,
                  backgroundImage: n.fromUser.avatarUrl != null
                      ? CachedNetworkImageProvider(n.fromUser.avatarUrl!)
                      : null,
                  child: n.fromUser.avatarUrl == null
                      ? Text(
                          n.fromUser.username[0].toUpperCase(),
                          style: SeeUTypography.subtitle.copyWith(
                            color: SeeUColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _notifIconColor(n.type),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: SeeUColors.background, width: 2),
                    ),
                    child: Center(
                      child: Icon(_notifIcon(n.type),
                          size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${n.fromUser.username} ',
                          style: SeeUTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: SeeUColors.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: n.message,
                          style: SeeUTypography.caption.copyWith(
                            color: SeeUColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(n.createdAt),
                    style: SeeUTypography.micro.copyWith(
                      color: SeeUColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Post thumbnail
            if (n.postThumbnailUrl != null) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: n.postThumbnailUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 48,
                    height: 48,
                    color: SeeUColors.borderSubtle,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    color: SeeUColors.borderSubtle,
                    child: Icon(
                      PhosphorIcons.image(),
                      size: 18,
                      color: SeeUColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIcons.bell(),
            size: 64,
            color: SeeUColors.borderSubtle,
          ),
          const SizedBox(height: 16),
          Text(
            _activeFilter != _NotifFilter.all
                ? 'Нет уведомлений этого типа'
                : 'Нет уведомлений',
            style: SeeUTypography.subtitle.copyWith(
              color: SeeUColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Здесь появятся ваши уведомления',
            style: SeeUTypography.caption.copyWith(
              color: SeeUColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
