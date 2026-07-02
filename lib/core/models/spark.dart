/// Отправитель Spark 🔥 — виден только владельцу профиля (GET /sparks/senders).
class SparkSender {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;
  final DateTime sentAt;

  const SparkSender({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
    required this.sentAt,
  });

  factory SparkSender.fromJson(Map<String, dynamic> j) => SparkSender(
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
        sentAt: j['sent_at'] != null
            ? DateTime.tryParse(j['sent_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}
