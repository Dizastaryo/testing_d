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
  /// §05: человекочитаемый текст ссылки — показывается в профиле вместо
  /// сырого URL (тап по-прежнему открывает website).
  final String? websiteLabel;
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
  /// true = у viewer есть NFC-касание браслетом или совпадение в контактах с
  /// этим юзером — без этого «Запросить доступ» будет отклонён сервером
  /// (403), кнопка на UI скрывается. Не приходит для own-profile (viewer==self).
  final bool canRequestAccess;
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
  final bool isAdmin;
  final String channelAbout;
  final String channelBannerUrl;
  // Scanner visibility toggle
  final bool scanEnabled;
  // ── Карточка (анонимная, для BLE-сканера) ──────────────────────────────────
  // Отдельно от профиля: никнейм/фото/текст карточки НЕ совпадают с реальными.
  final String scanAlias;    // никнейм карточки
  final String scanPhotoUrl; // фото карточки (обязательное поле карточки)
  final String scanText;     // текст/цитата карточки
  final String scanEmoji;    // акцентный эмодзи оформления
  final String scanStyle;    // JSON визуального оформления
  /// true = карточка уже создавалась. Если false — при входе в редактор
  /// обязателен полноэкранный экран предупреждения (нельзя пропустить).
  bool get hasCard =>
      scanPhotoUrl.isNotEmpty || scanAlias.isNotEmpty || scanText.isNotEmpty;
  /// Суммарный социальный счёт из user_stats.total_likes.
  final int totalLikes;
  final int socialLevel;
  final String socialLevelName;
  final int nextMilestone;
  // Монеты — legacy (заменены Spark). Счётчики оставлены дормантными.
  final int coinsCharisma;
  final int coinsLiked;
  final int coinsWorthy;
  // Spark 🔥 — количество полученных (Фаза 3).
  final int sparksCount;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    this.phone,
    required this.fullName,
    this.bio,
    this.website,
    this.websiteLabel,
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
    this.canRequestAccess = false,
    this.isOnline = false,
    this.lastSeenAt,
    this.hideLastSeen = false,
    this.isAdmin = false,
    this.channelAbout = '',
    this.channelBannerUrl = '',
    this.scanEnabled = true,
    this.scanAlias = '',
    this.scanPhotoUrl = '',
    this.scanText = '',
    this.scanEmoji = '',
    this.scanStyle = '',
    this.totalLikes = 0,
    this.socialLevel = 0,
    this.socialLevelName = 'Новичок',
    this.nextMilestone = 50,
    this.coinsCharisma = 0,
    this.coinsLiked = 0,
    this.coinsWorthy = 0,
    this.sparksCount = 0,
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
      websiteLabel: json['website_label']?.toString(),
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
      canRequestAccess: (json['can_request_access'] as bool?) ?? false,
      isOnline: (json['is_online'] as bool?) ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      hideLastSeen: (json['hide_last_seen'] as bool?) ?? false,
      isAdmin: (json['is_admin'] as bool?) ?? false,
      channelAbout: json['channel_about']?.toString() ?? '',
      channelBannerUrl: _absUrl(json['channel_banner_url']?.toString()),
      scanEnabled: (json['scan_enabled'] as bool?) ?? true,
      scanAlias: json['scan_alias']?.toString() ?? '',
      scanPhotoUrl: _absUrl(json['scan_avatar_url']?.toString()),
      scanText: json['scan_status']?.toString() ?? '',
      scanEmoji: json['scan_emoji']?.toString() ?? '',
      scanStyle: json['scan_style']?.toString() ?? '',
      totalLikes: ((json['total_likes']) as num?)?.toInt() ?? 0,
      socialLevel: ((json['social_level']) as num?)?.toInt() ?? 0,
      socialLevelName: json['social_level_name']?.toString() ?? 'Новичок',
      nextMilestone: ((json['next_milestone']) as num?)?.toInt() ?? 50,
      coinsCharisma: ((json['coins_charisma']) as num?)?.toInt() ?? 0,
      coinsLiked: ((json['coins_liked']) as num?)?.toInt() ?? 0,
      coinsWorthy: ((json['coins_worthy']) as num?)?.toInt() ?? 0,
      sparksCount: ((json['sparks_count']) as num?)?.toInt() ?? 0,
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
      'website_label': websiteLabel,
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
      'social_level': socialLevel,
      'social_level_name': socialLevelName,
      'next_milestone': nextMilestone,
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
    String? websiteLabel,
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
    bool? canRequestAccess,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool? hideLastSeen,
    bool? isAdmin,
    String? channelAbout,
    String? channelBannerUrl,
    bool? scanEnabled,
    String? scanAlias,
    String? scanPhotoUrl,
    String? scanText,
    String? scanEmoji,
    String? scanStyle,
    int? totalLikes,
    int? coinsCharisma,
    int? coinsLiked,
    int? coinsWorthy,
    int? sparksCount,
    int? socialLevel,
    String? socialLevelName,
    int? nextMilestone,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      website: website ?? this.website,
      websiteLabel: websiteLabel ?? this.websiteLabel,
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
      canRequestAccess: canRequestAccess ?? this.canRequestAccess,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      hideLastSeen: hideLastSeen ?? this.hideLastSeen,
      isAdmin: isAdmin ?? this.isAdmin,
      channelAbout: channelAbout ?? this.channelAbout,
      channelBannerUrl: channelBannerUrl ?? this.channelBannerUrl,
      scanEnabled: scanEnabled ?? this.scanEnabled,
      scanAlias: scanAlias ?? this.scanAlias,
      scanPhotoUrl: scanPhotoUrl ?? this.scanPhotoUrl,
      scanText: scanText ?? this.scanText,
      scanEmoji: scanEmoji ?? this.scanEmoji,
      scanStyle: scanStyle ?? this.scanStyle,
      totalLikes: totalLikes ?? this.totalLikes,
      coinsCharisma: coinsCharisma ?? this.coinsCharisma,
      coinsLiked: coinsLiked ?? this.coinsLiked,
      coinsWorthy: coinsWorthy ?? this.coinsWorthy,
      sparksCount: sparksCount ?? this.sparksCount,
      // Раньше эти три поля здесь отсутствовали — ЛЮБОЙ copyWith (presence,
      // follow-тоггл) молча сбрасывал соц-уровень на дефолты.
      socialLevel: socialLevel ?? this.socialLevel,
      socialLevelName: socialLevelName ?? this.socialLevelName,
      nextMilestone: nextMilestone ?? this.nextMilestone,
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
