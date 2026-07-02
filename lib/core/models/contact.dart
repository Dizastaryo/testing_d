/// Найденный в SeeU пользователь из контактов телефона + статус доступа.
/// Возврат POST /contacts/sync (Фаза 2).
class ContactMatch {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;

  /// Доступ уже открыт — можно писать.
  final bool hasAccess;

  /// Текущий пользователь уже отправил заявку этому контакту.
  final bool requestSent;

  const ContactMatch({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
    required this.hasAccess,
    required this.requestSent,
  });

  factory ContactMatch.fromJson(Map<String, dynamic> j) => ContactMatch(
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
        hasAccess: (j['has_access'] as bool?) ?? false,
        requestSent: (j['request_sent'] as bool?) ?? false,
      );
}
