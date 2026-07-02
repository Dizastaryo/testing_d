class AccessPartner {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;
  final DateTime grantedAt;

  const AccessPartner({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
    required this.grantedAt,
  });

  factory AccessPartner.fromJson(Map<String, dynamic> j) => AccessPartner(
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
        grantedAt: j['granted_at'] != null
            ? DateTime.tryParse(j['granted_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

/// Pending access request (request → accept/reject). [user] is the OTHER party:
/// for an incoming request it's the sender, for a sent one it's the addressee.
class AccessRequest {
  final String id;
  final AccessRequestUser user;
  final DateTime createdAt;

  const AccessRequest({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  factory AccessRequest.fromJson(Map<String, dynamic> j) => AccessRequest(
        id: j['id']?.toString() ?? '',
        user: AccessRequestUser.fromJson(
            (j['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

class AccessRequestUser {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;

  const AccessRequestUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
  });

  factory AccessRequestUser.fromJson(Map<String, dynamic> j) => AccessRequestUser(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
      );
}

