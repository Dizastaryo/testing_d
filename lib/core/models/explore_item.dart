import '../api/api_endpoints.dart';

/// The unified, backend-owned Explore card type (matches the Go ExploreItem).
enum ExploreItemType { post, short, video }

ExploreItemType _parseItemType(String? raw) {
  switch (raw) {
    case 'short':
      return ExploreItemType.short;
    case 'video':
      return ExploreItemType.video;
    case 'post':
    default:
      return ExploreItemType.post;
  }
}

String _abs(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class ExploreAuthor {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;

  const ExploreAuthor({
    this.id = '',
    this.username = '',
    this.fullName = '',
    this.avatarUrl = '',
  });

  factory ExploreAuthor.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ExploreAuthor();
    return ExploreAuthor(
      id: j['id']?.toString() ?? '',
      username: j['username']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      avatarUrl: _abs(j['avatar_url']?.toString()),
    );
  }
}

/// One mixed Explore feed item. `type` decides how it is rendered and routed:
///   post  → `/view/<postId>`
///   short → `/videos?initialVideoId=<videoId>&source=explore`
///   video → video detail
class ExploreItem {
  final String id;
  final ExploreItemType type;
  final String? postId;
  final String? videoId;
  final String? title;
  final String? caption;
  final String? thumbnailUrl;
  final String? imageUrl;
  final ExploreAuthor author;
  final int likesCount;
  final int viewsCount;
  final int commentsCount;
  final DateTime createdAt;
  final int durationSeconds;
  final int width;
  final int height;
  final double aspectRatio;
  final bool isShort;
  final bool isVideoPost;
  final String? sourceReason;

  const ExploreItem({
    required this.id,
    required this.type,
    this.postId,
    this.videoId,
    this.title,
    this.caption,
    this.thumbnailUrl,
    this.imageUrl,
    this.author = const ExploreAuthor(),
    this.likesCount = 0,
    this.viewsCount = 0,
    this.commentsCount = 0,
    required this.createdAt,
    this.durationSeconds = 0,
    this.width = 0,
    this.height = 0,
    this.aspectRatio = 0,
    this.isShort = false,
    this.isVideoPost = false,
    this.sourceReason,
  });

  /// The id used for routing / tracking: post_id for posts, video_id otherwise.
  String? get entityId => type == ExploreItemType.post ? postId : videoId;

  /// Best image to show in the grid (thumbnail preferred, else image_url).
  String get displayImage {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) return thumbnailUrl!;
    return imageUrl ?? '';
  }

  /// entity_type string used for interest tracking.
  String get entityTypeName {
    switch (type) {
      case ExploreItemType.short:
        return 'short';
      case ExploreItemType.video:
        return 'video';
      case ExploreItemType.post:
        return 'post';
    }
  }

  /// True when this item carries the id it needs to be opened. Items failing
  /// this are skipped by the UI (no crash, no broken card).
  bool get isOpenable => (entityId ?? '').isNotEmpty;

  factory ExploreItem.fromJson(Map<String, dynamic> j) {
    return ExploreItem(
      id: j['id']?.toString() ?? '',
      type: _parseItemType(j['item_type']?.toString()),
      postId: j['post_id']?.toString(),
      videoId: j['video_id']?.toString(),
      title: j['title']?.toString(),
      caption: j['caption']?.toString(),
      thumbnailUrl: _abs(j['thumbnail_url']?.toString()),
      imageUrl: _abs(j['image_url']?.toString()),
      author: ExploreAuthor.fromJson(
          j['author'] is Map ? (j['author'] as Map).cast<String, dynamic>() : null),
      likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
      viewsCount: (j['views_count'] as num?)?.toInt() ?? 0,
      commentsCount: (j['comments_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
          DateTime.now(),
      durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
      width: (j['width'] as num?)?.toInt() ?? 0,
      height: (j['height'] as num?)?.toInt() ?? 0,
      aspectRatio: (j['aspect_ratio'] as num?)?.toDouble() ?? 0,
      isShort: j['is_short'] == true,
      isVideoPost: j['is_video_post'] == true,
      sourceReason: j['source_reason']?.toString(),
    );
  }
}
