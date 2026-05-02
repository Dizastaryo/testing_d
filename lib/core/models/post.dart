import 'user.dart';

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
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final bool isSaved;
  final String? likedByUsername;
  final DateTime createdAt;
  final bool isWave;
  final int? waveColorValue;

  const Post({
    required this.id,
    required this.author,
    required this.media,
    this.caption,
    this.location,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.likedByUsername,
    required this.createdAt,
    this.isWave = false,
    this.waveColorValue,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // Support both structured 'media' array and flat 'media_urls' + 'media_types'
    List<PostMedia> mediaList;
    if (json['media'] is List && (json['media'] as List).isNotEmpty) {
      mediaList = (json['media'] as List)
          .map((m) => PostMedia.fromJson(m as Map<String, dynamic>))
          .toList();
    } else if (json['media_urls'] is List) {
      final urls = (json['media_urls'] as List).cast<String>();
      final types = json['media_types'] is List
          ? (json['media_types'] as List).cast<String>()
          : <String>[];
      mediaList = List.generate(urls.length, (i) {
        return PostMedia(
          url: urls[i],
          type: PostMedia._parseMediaType(i < types.length ? types[i] : null),
        );
      });
    } else {
      mediaList = [];
    }

    // Support both 'author' and 'user' keys for the post author
    final authorJson = (json['author'] ?? json['user']) as Map<String, dynamic>? ?? {};

    return Post(
      id: json['id']?.toString() ?? '',
      author: User.fromJson(authorJson),
      media: mediaList,
      caption: json['caption']?.toString(),
      location: json['location']?.toString(),
      likesCount: (json['likes_count'] ?? json['likesCount'] ?? 0) as int,
      commentsCount: (json['comments_count'] ?? json['commentsCount'] ?? 0) as int,
      isLiked: (json['is_liked'] ?? json['isLiked'] ?? false) as bool,
      isSaved: (json['is_saved'] ?? json['isSaved'] ?? false) as bool,
      likedByUsername: json['liked_by_username']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isWave: (json['is_wave'] ?? json['isWave'] ?? false) as bool,
      waveColorValue: (json['wave_color_value'] ?? json['waveColorValue']) as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.toJson(),
    'media': media.map((m) => m.toJson()).toList(),
    'caption': caption,
    'location': location,
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
    int? likesCount,
    int? commentsCount,
    bool? isLiked,
    bool? isSaved,
    String? likedByUsername,
    DateTime? createdAt,
    bool? isWave,
    int? waveColorValue,
  }) {
    return Post(
      id: id ?? this.id,
      author: author ?? this.author,
      media: media ?? this.media,
      caption: caption ?? this.caption,
      location: location ?? this.location,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      likedByUsername: likedByUsername ?? this.likedByUsername,
      createdAt: createdAt ?? this.createdAt,
      isWave: isWave ?? this.isWave,
      waveColorValue: waveColorValue ?? this.waveColorValue,
    );
  }

}
