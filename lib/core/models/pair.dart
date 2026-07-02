/// Партнёр в паре/промпте (Фаза 5).
class PairUser {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;

  const PairUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
  });

  factory PairUser.fromJson(Map<String, dynamic> j) => PairUser(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
      );
}

/// Ожидающий подтверждения промпт пары.
class PairPrompt {
  final String id;
  final PairUser user;
  final DateTime createdAt;

  const PairPrompt({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  factory PairPrompt.fromJson(Map<String, dynamic> j) => PairPrompt(
        id: j['id']?.toString() ?? '',
        user: PairUser.fromJson(
            (j['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}
