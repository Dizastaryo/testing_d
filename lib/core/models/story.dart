import '../api/api_endpoints.dart';
import 'user.dart';

String _toAbsUrl(String url) {
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

enum StoryMediaType { image, video }

class Story {
  final String id;
  final User author;
  final String mediaUrl;
  final StoryMediaType mediaType;
  final String? textOverlay;
  final bool isSeen;
  final int viewsCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  /// Aggregate emoji-reaction counts per emoji (server-aggregated). Visible
  /// to author for analytics; viewers see it too but UI rarely renders
  /// counts for non-authors.
  final Map<String, int> reactions;
  /// Emoji the *current viewer* placed on this story; empty when none.
  final String myReaction;

  const Story({
    required this.id,
    required this.author,
    required this.mediaUrl,
    this.mediaType = StoryMediaType.image,
    this.textOverlay,
    this.isSeen = false,
    this.viewsCount = 0,
    required this.createdAt,
    required this.expiresAt,
    this.reactions = const {},
    this.myReaction = '',
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      author: User.fromJson((json['author'] ?? json['user']) as Map<String, dynamic>? ?? {}),
      mediaUrl: _toAbsUrl(json['media_url']?.toString() ?? ''),
      mediaType: json['media_type'] == 'video'
          ? StoryMediaType.video
          : StoryMediaType.image,
      textOverlay: json['text_overlay']?.toString(),
      isSeen: (json['is_seen'] ?? json['isSeen'] ?? false) as bool,
      viewsCount: (json['views_count'] ?? 0) as int,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString()) ??
              DateTime.now().add(const Duration(hours: 24))
          : DateTime.now().add(const Duration(hours: 24)),
      reactions: json['reactions'] is Map
          ? Map<String, int>.from(
              (json['reactions'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toInt()),
              ),
            )
          : const {},
      myReaction: json['my_reaction']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.toJson(),
    'media_url': mediaUrl,
    'media_type': mediaType.name,
    'text_overlay': textOverlay,
    'is_seen': isSeen,
    'views_count': viewsCount,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
  };

  Story copyWith({
    bool? isSeen,
    int? viewsCount,
    Map<String, int>? reactions,
    String? myReaction,
  }) {
    return Story(
      id: id,
      author: author,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      textOverlay: textOverlay,
      isSeen: isSeen ?? this.isSeen,
      viewsCount: viewsCount ?? this.viewsCount,
      createdAt: createdAt,
      expiresAt: expiresAt,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
    );
  }
}

class StoryGroup {
  final User author;
  final List<Story> stories;
  final bool allSeen;

  const StoryGroup({
    required this.author,
    required this.stories,
    required this.allSeen,
  });

  factory StoryGroup.fromJson(Map<String, dynamic> json) {
    final storiesList = (json['stories'] as List?)
            ?.map((s) => Story.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];
    return StoryGroup(
      author: User.fromJson((json['author'] ?? json['user']) as Map<String, dynamic>? ?? {}),
      stories: storiesList,
      allSeen: storiesList.every((s) => s.isSeen),
    );
  }

}
