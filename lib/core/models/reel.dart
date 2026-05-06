import '../api/api_endpoints.dart';
import 'user.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.videoBaseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class Reel {
  final String id;
  final String userId;
  final String caption;
  final List<String> mediaUrls;
  final String mediaType;
  final String audioTrackId;
  final int durationSeconds;
  final int viewsCount;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final List<String> hashtags;
  final DateTime createdAt;
  final UserShort? user;
  final bool isLiked;

  Reel({
    required this.id,
    required this.userId,
    this.caption = '',
    required this.mediaUrls,
    this.mediaType = 'photo',
    this.audioTrackId = '',
    this.durationSeconds = 15,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.hashtags = const [],
    required this.createdAt,
    this.user,
    this.isLiked = false,
  });

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        caption: json['caption'] ?? '',
        mediaUrls: (json['media_urls'] as List<dynamic>?)?.map((e) => _absUrl(e.toString())).toList() ?? [],
        mediaType: json['media_type'] ?? 'photo',
        audioTrackId: json['audio_track_id'] ?? '',
        durationSeconds: json['duration_seconds'] ?? 15,
        viewsCount: json['views_count'] ?? 0,
        likesCount: json['likes_count'] ?? 0,
        commentsCount: json['comments_count'] ?? 0,
        sharesCount: json['shares_count'] ?? 0,
        hashtags: (json['hashtags'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        user: json['user'] != null ? UserShort.fromJson(json['user']) : null,
        isLiked: json['is_liked'] ?? false,
      );

  String get likesFormatted {
    if (likesCount >= 1000000) return '${(likesCount / 1000000).toStringAsFixed(1)}M';
    if (likesCount >= 1000) return '${(likesCount / 1000).toStringAsFixed(1)}K';
    return likesCount.toString();
  }

  String get commentsFormatted {
    if (commentsCount >= 1000) return '${(commentsCount / 1000).toStringAsFixed(1)}K';
    return commentsCount.toString();
  }
}
