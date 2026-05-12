import '../api/api_endpoints.dart';
import 'user.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.videoBaseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class VideoCategory {
  final String id;
  final String name;

  VideoCategory({required this.id, required this.name});

  factory VideoCategory.fromJson(Map<String, dynamic> json) => VideoCategory(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
      );
}

class Video {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final int durationSeconds;
  final String categoryId;
  final String resolution;
  final int viewsCount;
  final int likesCount;
  final int commentsCount;
  final bool isLive;
  final DateTime createdAt;
  final UserShort? user;
  final VideoCategory? category;
  final bool isLiked;
  /// VIDEO-5: URL VTT-файла с субтитрами. Пустая = без субтитров. Плеер
  /// подгружает дорожку асинхронно при первом включении CC-кнопки.
  final String subtitlesUrl;

  Video({
    required this.id,
    required this.userId,
    required this.title,
    this.description = '',
    required this.videoUrl,
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.categoryId = '',
    this.resolution = '',
    this.viewsCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLive = false,
    required this.createdAt,
    this.user,
    this.category,
    this.isLiked = false,
    this.subtitlesUrl = '',
  });

  factory Video.fromJson(Map<String, dynamic> json) => Video(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        videoUrl: _absUrl(json['video_url']),
        thumbnailUrl: _absUrl(json['thumbnail_url']),
        durationSeconds: json['duration_seconds'] ?? 0,
        categoryId: json['category_id'] ?? '',
        resolution: json['resolution'] ?? '',
        viewsCount: json['views_count'] ?? 0,
        likesCount: json['likes_count'] ?? 0,
        commentsCount: json['comments_count'] ?? 0,
        isLive: json['is_live'] ?? false,
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        user: json['user'] != null ? UserShort.fromJson(json['user']) : null,
        category: json['category'] != null ? VideoCategory.fromJson(json['category']) : null,
        isLiked: json['is_liked'] ?? false,
        subtitlesUrl: _absUrl(json['subtitles_url']),
      );

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get viewsFormatted {
    if (viewsCount >= 1000000) return '${(viewsCount / 1000000).toStringAsFixed(1)}M';
    if (viewsCount >= 1000) return '${(viewsCount / 1000).toStringAsFixed(0)}K';
    return viewsCount.toString();
  }
}
