import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/tokens.dart';

// ─── Category ────────────────────────────────────────────────────

enum SborCategory {
  basketball,
  hike,
  games,
  board,
  cinema,
  draw,
  read,
  food,
  music,
  other,
}

class SborCategoryMeta {
  final String name;
  final Color color;
  final Color soft;
  final IconData icon;

  const SborCategoryMeta({
    required this.name,
    required this.color,
    required this.soft,
    required this.icon,
  });
}

const Map<SborCategory, SborCategoryMeta> kSborCategories = {
  SborCategory.basketball: SborCategoryMeta(
    name: 'Спорт',
    color: SeeUColors.accent,
    soft: SeeUColors.accentSoft,
    icon: PhosphorIconsRegular.basketball,
  ),
  SborCategory.hike: SborCategoryMeta(
    name: 'Природа',
    color: SeeUColors.success,
    soft: Color(0xFFDDF1E1),
    icon: PhosphorIconsRegular.mountains,
  ),
  SborCategory.games: SborCategoryMeta(
    name: 'Игры',
    color: SeeUColors.plum,
    soft: Color(0xFFF2E0FE),
    icon: PhosphorIconsRegular.gameController,
  ),
  SborCategory.board: SborCategoryMeta(
    name: 'Настолки',
    color: SeeUColors.like,
    soft: Color(0xFFFFE1E9),
    icon: PhosphorIconsRegular.diceFive,
  ),
  SborCategory.cinema: SborCategoryMeta(
    name: 'Кино',
    color: SeeUColors.like,
    soft: Color(0xFFFFE1E9),
    icon: PhosphorIconsRegular.filmStrip,
  ),
  SborCategory.draw: SborCategoryMeta(
    name: 'Творчество',
    color: SeeUColors.amber,
    soft: Color(0xFFFFEFD2),
    icon: PhosphorIconsRegular.paintBrush,
  ),
  SborCategory.read: SborCategoryMeta(
    name: 'Книги',
    color: Color(0xFF5DB1FF),
    soft: Color(0xFFDEEEFE),
    icon: PhosphorIconsRegular.book,
  ),
  SborCategory.food: SborCategoryMeta(
    name: 'Готовим',
    color: SeeUColors.amber,
    soft: Color(0xFFFFEFD2),
    icon: PhosphorIconsRegular.forkKnife,
  ),
  SborCategory.music: SborCategoryMeta(
    name: 'Музыка',
    color: SeeUColors.amber,
    soft: Color(0xFFFFEFD2),
    icon: PhosphorIconsRegular.musicNote,
  ),
  SborCategory.other: SborCategoryMeta(
    name: 'Другое',
    color: SeeUColors.textSecondary,
    soft: SeeUColors.surface2,
    icon: PhosphorIconsFill.star,
  ),
};

SborCategory sborCategoryFromString(String s) {
  return SborCategory.values.firstWhere(
    (e) => e.name == s,
    orElse: () => SborCategory.other,
  );
}

// ─── Model ───────────────────────────────────────────────────────

enum SborType { offline, online }

enum SborRole { none, participant, organizer }

class Sbor {
  final String id;
  final SborType type;
  final SborCategory category;
  final String title;
  final String hostName;
  final String hostId;
  final String when;
  final String? whenSub;
  final String place;
  final String? distance;
  final bool live;
  final int joined;
  final int? max; // null = no limit
  final List<String> memberNames;
  final List<String> memberUsernames;
  final List<String> memberIds;
  final String? coverUrl;
  final int price;
  final String? description;
  final SborRole myRole;
  final bool isJoined;
  final bool isBookmarked;
  final String? chatId;
  final DateTime? scheduledAt;
  // Request flow
  final String myRequestStatus;    // '' | 'pending' | 'approved' | 'rejected'
  final int pendingRequestsCount;  // visible to organizer only

  const Sbor({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.hostName,
    required this.hostId,
    required this.when,
    this.whenSub,
    required this.place,
    this.distance,
    this.live = false,
    required this.joined,
    this.max,
    this.memberNames = const [],
    this.memberUsernames = const [],
    this.memberIds = const [],
    this.coverUrl,
    this.price = 0,
    this.description,
    this.myRole = SborRole.none,
    this.isJoined = false,
    this.isBookmarked = false,
    this.chatId,
    this.scheduledAt,
    this.myRequestStatus = '',
    this.pendingRequestsCount = 0,
  });

  int get remaining => max == null ? 999 : max! - joined;
  bool get isFull => max != null && joined >= max!;
  bool get isPast => scheduledAt != null && scheduledAt!.isBefore(DateTime.now());

  SborCategoryMeta get categoryMeta =>
      kSborCategories[category] ?? kSborCategories[SborCategory.other]!;

  factory Sbor.fromJson(Map<String, dynamic> j) {
    return Sbor(
      id: j['id'] as String,
      type: j['type'] == 'online' ? SborType.online : SborType.offline,
      category: sborCategoryFromString(j['category'] as String? ?? 'other'),
      title: j['title'] as String,
      hostName: j['host_name'] as String? ?? '',
      hostId: j['host_id'] as String? ?? '',
      when: j['when'] as String? ?? '',
      whenSub: j['when_sub'] as String?,
      place: j['place'] as String? ?? '',
      distance: j['distance'] as String?,
      live: j['live'] as bool? ?? false,
      joined: j['joined'] as int? ?? 0,
      max: j['max'] as int?,
      memberNames: (j['member_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      memberUsernames: (j['member_usernames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      memberIds: (j['member_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      coverUrl: j['cover_url'] as String?,
      price: j['price'] as int? ?? 0,
      description: j['description'] as String?,
      myRole: _roleFromString(j['my_role'] as String?),
      isJoined: j['is_joined'] as bool? ?? false,
      isBookmarked: j['is_bookmarked'] as bool? ?? false,
      chatId: j['chat_id'] as String?,
      scheduledAt: j['scheduled_at'] != null
          ? DateTime.tryParse(j['scheduled_at'] as String)
          : null,
      myRequestStatus: j['my_request_status'] as String? ?? '',
      pendingRequestsCount: j['pending_requests_count'] as int? ?? 0,
    );
  }

  static SborRole _roleFromString(String? s) {
    switch (s) {
      case 'organizer':
        return SborRole.organizer;
      case 'participant':
        return SborRole.participant;
      default:
        return SborRole.none;
    }
  }
}

// ─── Join Request ─────────────────────────────────────────────────

class SborJoinRequest {
  final String id;
  final String sborId;
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final String status; // pending | approved | rejected
  final String message;
  final DateTime createdAt;

  const SborJoinRequest({
    required this.id,
    required this.sborId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  factory SborJoinRequest.fromJson(Map<String, dynamic> j) {
    return SborJoinRequest(
      id: j['id'] as String,
      sborId: j['sbor_id'] as String,
      userId: j['user_id'] as String,
      username: j['username'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      avatarUrl: j['avatar_url'] as String? ?? '',
      status: j['status'] as String? ?? 'pending',
      message: j['message'] as String? ?? '',
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
