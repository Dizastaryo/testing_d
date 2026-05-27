import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/tokens.dart';

// ─── Category ────────────────────────────────────────────────────

enum SborCategory {
  basketball,
  hike,
  games,
  coop,
  fifa,
  board,
  cinema,
  run,
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
  SborCategory.coop: SborCategoryMeta(
    name: 'Кооператив',
    color: SeeUColors.plum,
    soft: Color(0xFFF2E0FE),
    icon: PhosphorIconsRegular.gameController,
  ),
  SborCategory.fifa: SborCategoryMeta(
    name: 'Спорт',
    color: SeeUColors.accent,
    soft: SeeUColors.accentSoft,
    icon: PhosphorIconsRegular.basketball,
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
  SborCategory.run: SborCategoryMeta(
    name: 'Спорт',
    color: SeeUColors.accent,
    soft: SeeUColors.accentSoft,
    icon: PhosphorIconsRegular.basketball,
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
  final String? description;
  final SborRole myRole;
  final bool isJoined;
  final String? chatId;
  final DateTime? scheduledAt;

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
    this.description,
    this.myRole = SborRole.none,
    this.isJoined = false,
    this.chatId,
    this.scheduledAt,
  });

  int get remaining => max == null ? 999 : max! - joined;
  bool get isFull => max != null && joined >= max!;

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
      description: j['description'] as String?,
      myRole: _roleFromString(j['my_role'] as String?),
      isJoined: j['is_joined'] as bool? ?? false,
      chatId: j['chat_id'] as String?,
      scheduledAt: j['scheduled_at'] != null
          ? DateTime.tryParse(j['scheduled_at'] as String)
          : null,
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
