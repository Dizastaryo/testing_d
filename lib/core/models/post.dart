import '../api/api_endpoints.dart';
import 'user.dart';

String _toAbsoluteUrl(String url) {
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

enum MediaType { image, video, carousel }

class PostMedia {
  final String url;
  final MediaType type;
  final String? thumbnailUrl;
  final double? aspectRatio;

  const PostMedia({
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.aspectRatio,
  });

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    return PostMedia(
      url: json['url']?.toString() ?? '',
      type: _parseMediaType(json['type']?.toString()),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      aspectRatio: (json['aspect_ratio'] as num?)?.toDouble(),
    );
  }

  static MediaType _parseMediaType(String? type) {
    switch (type) {
      case 'video':
        return MediaType.video;
      case 'carousel':
        return MediaType.carousel;
      default:
        return MediaType.image;
    }
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type.name,
    'thumbnail_url': thumbnailUrl,
    'aspect_ratio': aspectRatio,
  };
}

class Post {
  final String id;
  final User author;
  final List<PostMedia> media;
  final String? caption;
  final String? location;
  final String? thumbnailUrl;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final bool isSaved;
  final String? likedByUsername;
  final DateTime createdAt;
  final bool isWave;
  final int? waveColorValue;
  /// REELS-4: id audio-track'а если пост создан с music overlay. null/empty
  /// = без фоновой музыки. Reels-viewer показывает pill «🎵 Track» → tap =
  /// camera с pre-selected audio.
  final String? audioTrackId;
  /// Where in the track playback starts. Photo posts loop the track from here;
  /// video posts overlay it from here.
  final int audioStartSeconds;
  /// Sound-bridge: название и автор прикреплённого трека (гидрируются бэком из
  /// audio_tracks). Пустые, когда у поста нет трека. Лента рисует
  /// «🎵 название · автор» под именем автора.
  final String audioTrackTitle;
  final String audioTrackArtist;

  const Post({
    required this.id,
    required this.author,
    required this.media,
    this.caption,
    this.location,
    this.thumbnailUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.likedByUsername,
    required this.createdAt,
    this.isWave = false,
    this.waveColorValue,
    this.audioTrackId,
    this.audioStartSeconds = 0,
    this.audioTrackTitle = '',
    this.audioTrackArtist = '',
  });

  /// URL подходящий для grid-cell'а (Explore / Profile / chat-share preview).
  /// Для видео-постов — `thumbnailUrl` если задан (видео не отрендерится в
  /// grid-картинке). Для фото-постов — первая media URL. Empty string когда
  /// у поста вообще нет медиа.
  String get gridThumbnailUrl {
    final isVideo = media.any((m) => m.type == MediaType.video);
    if (isVideo && thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl!;
    }
    return media.isNotEmpty ? media.first.url : '';
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    // Support both structured 'media' array and flat 'media_urls' + 'media_types'
    List<PostMedia> mediaList;
    if (json['media'] is List && (json['media'] as List).isNotEmpty) {
      mediaList = (json['media'] as List)
          .map((m) => PostMedia.fromJson(m as Map<String, dynamic>))
          .toList();
    } else if (json['media_urls'] is List) {
      final urls = (json['media_urls'] as List)
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      final types = json['media_types'] is List
          ? (json['media_types'] as List).cast<String>()
          : <String>[];
      mediaList = List.generate(urls.length, (i) {
        return PostMedia(
          url: _toAbsoluteUrl(urls[i]),
          type: PostMedia._parseMediaType(i < types.length ? types[i] : null),
        );
      });
    } else {
      mediaList = [];
    }

    // Support both 'author' and 'user' keys for the post author
    final rawAuthor = json['author'] ?? json['user'];
    final authorJson =
        rawAuthor is Map ? rawAuthor.cast<String, dynamic>() : <String, dynamic>{};

    // Parse thumbnail_url
    final rawThumb = json['thumbnail_url']?.toString();
    final thumbnailUrl = (rawThumb != null && rawThumb.isNotEmpty)
        ? _toAbsoluteUrl(rawThumb)
        : null;

    return Post(
      id: json['id']?.toString() ?? '',
      author: User.fromJson(authorJson),
      media: mediaList,
      caption: json['caption']?.toString(),
      location: json['location']?.toString(),
      thumbnailUrl: thumbnailUrl,
      // BUG-20: num? для всех счётчиков защищает от типа double (BIGINT).
      likesCount: ((json['likes_count'] ?? json['likesCount']) as num?)?.toInt() ?? 0,
      commentsCount: ((json['comments_count'] ?? json['commentsCount']) as num?)?.toInt() ?? 0,
      isLiked: ((json['is_liked'] ?? json['isLiked']) as bool?) ?? false,
      isSaved: ((json['is_saved'] ?? json['isSaved']) as bool?) ?? false,
      likedByUsername: json['liked_by_username']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isWave: ((json['is_wave'] ?? json['isWave']) as bool?) ?? false,
      waveColorValue: ((json['wave_color_value'] ?? json['waveColorValue']) as num?)?.toInt(),
      audioTrackId: () {
        final v = json['audio_track_id']?.toString() ?? '';
        return v.isEmpty ? null : v;
      }(),
      audioStartSeconds: (json['audio_start_seconds'] as num?)?.toInt() ?? 0,
      audioTrackTitle: json['audio_track_title']?.toString() ?? '',
      audioTrackArtist: json['audio_track_artist']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.toJson(),
    'media': media.map((m) => m.toJson()).toList(),
    'caption': caption,
    'location': location,
    'thumbnail_url': thumbnailUrl,
    'likes_count': likesCount,
    'comments_count': commentsCount,
    'is_liked': isLiked,
    'is_saved': isSaved,
    'liked_by_username': likedByUsername,
    'created_at': createdAt.toIso8601String(),
    'is_wave': isWave,
    'wave_color_value': waveColorValue,
  };

  Post copyWith({
    String? id,
    User? author,
    List<PostMedia>? media,
    String? caption,
    String? location,
    String? thumbnailUrl,
    int? likesCount,
    int? commentsCount,
    bool? isLiked,
    bool? isSaved,
    String? likedByUsername,
    DateTime? createdAt,
    bool? isWave,
    int? waveColorValue,
    String? audioTrackId,
    int? audioStartSeconds,
    String? audioTrackTitle,
    String? audioTrackArtist,
  }) {
    return Post(
      id: id ?? this.id,
      author: author ?? this.author,
      media: media ?? this.media,
      caption: caption ?? this.caption,
      location: location ?? this.location,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      likedByUsername: likedByUsername ?? this.likedByUsername,
      createdAt: createdAt ?? this.createdAt,
      isWave: isWave ?? this.isWave,
      waveColorValue: waveColorValue ?? this.waveColorValue,
      audioTrackId: audioTrackId ?? this.audioTrackId,
      audioStartSeconds: audioStartSeconds ?? this.audioStartSeconds,
      audioTrackTitle: audioTrackTitle ?? this.audioTrackTitle,
      audioTrackArtist: audioTrackArtist ?? this.audioTrackArtist,
    );
  }

}
