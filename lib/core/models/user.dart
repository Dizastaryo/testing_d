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
    required this.createdAt,
  });

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
      postsCount: (json['posts_count'] ?? json['postsCount'] ?? 0) as int,
      followersCount: (json['followers_count'] ?? json['followersCount'] ?? 0) as int,
      followingCount: (json['following_count'] ?? json['followingCount'] ?? 0) as int,
      isFollowing: (json['is_following'] ?? json['isFollowing'] ?? false) as bool,
      isFollowedBy: (json['is_followed_by'] ?? json['isFollowedBy'] ?? false) as bool,
      isPrivate: (json['is_private'] ?? json['isPrivate'] ?? false) as bool,
      isVerified: (json['is_verified'] ?? json['isVerified'] ?? false) as bool,
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
