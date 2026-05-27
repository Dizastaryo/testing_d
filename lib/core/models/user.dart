import '../api/api_endpoints.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class User {
  final String id;
  final String username;
  final String? phone;
  final String fullName;
  final String? bio;
  final String? website;
  final String? avatarUrl;
  final String? gender;
  final String? dateOfBirth;
  final String? devicePublicId;
  final String? devicePrivateId;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isPrivate;
  final bool isVerified;
  /// true = viewer запросил подписку на этого приватного юзера, но запрос
  /// ещё не одобрен. Бэк возвращает только для приватных профилей с
  /// !isFollowing. Используется чтобы Follow-кнопка показывала
  /// «Запрос отправлен» вместо «Подписаться».
  final bool hasPendingFollowRequest;
  /// true = у юзера есть хотя бы одно активное WS-соединение (онлайн прямо
  /// сейчас). Снимок на момент запроса.
  final bool isOnline;
  /// Последнее обновление онлайн-статуса (connect или disconnect). Используется
  /// для «был N мин назад» когда isOnline=false.
  final DateTime? lastSeenAt;
  /// PROFILE-6 privacy: если юзер скрыл last_seen — бэк отдаёт false/zero
  /// другим зрителям, но self видит реальный статус. Поле нужно для toggle
  /// в edit_profile.
  final bool hideLastSeen;
  /// VIDEO-4 channel fields. Если оба пусты — обычный профиль; иначе UI
  /// рендерит channel-mode (hero-banner + about-text + Videos default tab).
  final String channelAbout;
  final String channelBannerUrl;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    this.phone,
    required this.fullName,
    this.bio,
    this.website,
    this.avatarUrl,
    this.gender,
    this.dateOfBirth,
    this.devicePublicId,
    this.devicePrivateId,
    this.postsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.isFollowedBy = false,
    this.isPrivate = false,
    this.isVerified = false,
    this.hasPendingFollowRequest = false,
    this.isOnline = false,
    this.lastSeenAt,
    this.hideLastSeen = false,
    this.channelAbout = '',
    this.channelBannerUrl = '',
    required this.createdAt,
  });

  /// VIDEO-4: true если у юзера заполнено что-то channel-специфичное —
  /// баннер или about. Тогда UI переходит в channel-mode.
  bool get isChannel =>
      channelBannerUrl.isNotEmpty || channelAbout.isNotEmpty;

  /// «в сети» / «был N мин назад» / «давно». Используется в шапке чата
  /// и в чат-листе. Если бэк не отдал lastSeenAt — возвращаем пустую строку.
  String presenceLabel() {
    if (isOnline) return 'в сети';
    final ls = lastSeenAt;
    if (ls == null) return '';
    final diff = DateTime.now().difference(ls);
    final wasFem = gender == 'female' || gender == 'f' || gender == 'женский';
    final was = wasFem ? 'была' : 'был';
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '$was ${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '$was ${diff.inHours} ч назад';
    if (diff.inDays < 7) return '$was ${diff.inDays} д назад';
    return 'давно';
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      phone: json['phone']?.toString(),
      fullName: json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      bio: json['bio']?.toString(),
      website: json['website']?.toString(),
      avatarUrl: _absUrl(json['avatar_url']?.toString() ?? json['avatarUrl']?.toString()),
      gender: json['gender']?.toString(),
      dateOfBirth: json['date_of_birth']?.toString(),
      devicePublicId: json['device_public_id']?.toString(),
      devicePrivateId: json['device_private_id']?.toString(),
      // num? для счётчиков (защита от BIGINT → double).
      postsCount: ((json['posts_count'] ?? json['postsCount']) as num?)?.toInt() ?? 0,
      followersCount: ((json['followers_count'] ?? json['followersCount']) as num?)?.toInt() ?? 0,
      followingCount: ((json['following_count'] ?? json['followingCount']) as num?)?.toInt() ?? 0,
      isFollowing: ((json['is_following'] ?? json['isFollowing']) as bool?) ?? false,
      isFollowedBy: ((json['is_followed_by'] ?? json['isFollowedBy']) as bool?) ?? false,
      isPrivate: ((json['is_private'] ?? json['isPrivate']) as bool?) ?? false,
      isVerified: ((json['is_verified'] ?? json['isVerified']) as bool?) ?? false,
      hasPendingFollowRequest:
          (json['has_pending_follow_request'] as bool?) ?? false,
      isOnline: (json['is_online'] as bool?) ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      hideLastSeen: (json['hide_last_seen'] as bool?) ?? false,
      channelAbout: json['channel_about']?.toString() ?? '',
      channelBannerUrl: _absUrl(json['channel_banner_url']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'phone': phone,
      'full_name': fullName,
      'bio': bio,
      'website': website,
      'avatar_url': avatarUrl,
      'gender': gender,
      'date_of_birth': dateOfBirth,
      'device_public_id': devicePublicId,
      'device_private_id': devicePrivateId,
      'posts_count': postsCount,
      'followers_count': followersCount,
      'following_count': followingCount,
      'is_following': isFollowing,
      'is_followed_by': isFollowedBy,
      'is_private': isPrivate,
      'is_verified': isVerified,
      'has_pending_follow_request': hasPendingFollowRequest,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserShort toShort() => UserShort(
        id: id,
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl ?? '',
        isVerified: isVerified,
      );

  User copyWith({
    String? id,
    String? username,
    String? phone,
    String? fullName,
    String? bio,
    String? website,
    String? avatarUrl,
    String? gender,
    String? dateOfBirth,
    String? devicePublicId,
    String? devicePrivateId,
    int? postsCount,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    bool? isFollowedBy,
    bool? isPrivate,
    bool? isVerified,
    bool? hasPendingFollowRequest,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool? hideLastSeen,
    String? channelAbout,
    String? channelBannerUrl,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      website: website ?? this.website,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      devicePublicId: devicePublicId ?? this.devicePublicId,
      devicePrivateId: devicePrivateId ?? this.devicePrivateId,
      postsCount: postsCount ?? this.postsCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isFollowedBy: isFollowedBy ?? this.isFollowedBy,
      isPrivate: isPrivate ?? this.isPrivate,
      isVerified: isVerified ?? this.isVerified,
      hasPendingFollowRequest:
          hasPendingFollowRequest ?? this.hasPendingFollowRequest,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      hideLastSeen: hideLastSeen ?? this.hideLastSeen,
      channelAbout: channelAbout ?? this.channelAbout,
      channelBannerUrl: channelBannerUrl ?? this.channelBannerUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class UserShort {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;

  const UserShort({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    this.isVerified = false,
  });

  factory UserShort.fromJson(Map<String, dynamic> json) => UserShort(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? '',
        avatarUrl: _absUrl(json['avatar_url']?.toString()),
        isVerified: (json['is_verified'] ?? false) as bool,
      );
}
