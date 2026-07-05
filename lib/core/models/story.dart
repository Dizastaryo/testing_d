import '../api/api_endpoints.dart';
import 'user.dart';

String _toAbsUrl(String url) {
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

enum StoryMediaType { image, video, text }

class Story {
  final String id;
  final User author;
  final String mediaUrl;
  final StoryMediaType mediaType;
  final String? textOverlay;
  final bool isSeen;
  final int viewsCount;
  final int likesCount;
  /// Persisted like state — whether the *current viewer* has liked this
  /// story, hydrated by the backend on every fetch (mirrors Post.isLiked).
  /// Previously stories had no such field, so the viewer had to track likes
  /// in a purely in-memory Set that reset on every viewer session.
  final bool isLiked;
  final DateTime createdAt;
  final DateTime expiresAt;
  /// Aggregate emoji-reaction counts per emoji (server-aggregated). Visible
  /// to author for analytics; viewers see it too but UI rarely renders
  /// counts for non-authors.
  final Map<String, int> reactions;
  /// Emoji the *current viewer* placed on this story; empty when none.
  final String myReaction;
  /// Audio-track UUID для photo-story (Spotify-style музыка). null = без музыки.
  /// Story-viewer лениво подгружает /audio-tracks/:id и проигрывает через just_audio.
  final String? audioTrackId;
  /// MUSIC-7: с какой секунды трека начать playback в viewer'е. 0 = с начала.
  final int audioStartSeconds;
  /// STORY-1: фон для text-сторис. Hex (#RRGGBB) или preset-имя градиента
  /// (sunset / ocean / forest / mono). Empty для image/video.
  final String bgColor;
  /// STORY-3: интерактивный poll-overlay. null = poll'а нет.
  final StoryPoll? poll;
  /// PROFILE-3: true = story видна только close_friends автора. Frontend
  /// stories-row рисует зелёный bordered ring вокруг preview-circle.
  final bool isCloseFriendsOnly;

  const Story({
    required this.id,
    required this.author,
    required this.mediaUrl,
    this.mediaType = StoryMediaType.image,
    this.textOverlay,
    this.isSeen = false,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.isLiked = false,
    required this.createdAt,
    required this.expiresAt,
    this.reactions = const {},
    this.myReaction = '',
    this.audioTrackId,
    this.audioStartSeconds = 0,
    this.bgColor = '',
    this.poll,
    this.isCloseFriendsOnly = false,
  });

  /// true если это text-сторис (без media, с фоном bg_color и текстом
  /// в text_overlay).
  bool get isText => mediaType == StoryMediaType.text;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      author: User.fromJson((json['author'] ?? json['user']) as Map<String, dynamic>? ?? {}),
      mediaUrl: _toAbsUrl(json['media_url']?.toString() ?? ''),
      mediaType: switch (json['media_type']) {
        'video' => StoryMediaType.video,
        'text' => StoryMediaType.text,
        _ => StoryMediaType.image,
      },
      textOverlay: json['text_overlay']?.toString(),
      isSeen: (json['is_seen'] ?? json['isSeen'] as bool?) ?? false,
      // BUG-20: num? для счётчика.
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      isLiked: (json['is_liked'] as bool?) ?? false,
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
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
              ),
            )
          : const {},
      myReaction: json['my_reaction']?.toString() ?? '',
      audioTrackId: json['audio_track_id']?.toString(),
      audioStartSeconds:
          (json['audio_start_seconds'] as num?)?.toInt() ?? 0,
      bgColor: json['bg_color']?.toString() ?? '',
      poll: json['poll'] is Map
          ? StoryPoll.fromJson(json['poll'] as Map<String, dynamic>)
          : null,
      isCloseFriendsOnly: (json['is_close_friends_only'] ?? false) as bool,
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
    'likes_count': likesCount,
    'is_liked': isLiked,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'audio_track_id': audioTrackId,
  };

  Story copyWith({
    bool? isSeen,
    int? viewsCount,
    int? likesCount,
    bool? isLiked,
    Map<String, int>? reactions,
    String? myReaction,
    StoryPoll? poll,
  }) {
    return Story(
      id: id,
      author: author,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      textOverlay: textOverlay,
      isSeen: isSeen ?? this.isSeen,
      viewsCount: viewsCount ?? this.viewsCount,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      expiresAt: expiresAt,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
      audioTrackId: audioTrackId,
      audioStartSeconds: audioStartSeconds,
      bgColor: bgColor,
      poll: poll ?? this.poll,
      isCloseFriendsOnly: isCloseFriendsOnly,
    );
  }
}

/// STORY-3: интерактивный poll-overlay поверх сторис. Question + два варианта.
/// votesA/votesB/myVote приходят с бэка hydrated per-viewer.
class StoryPoll {
  final String question;
  final String optionA;
  final String optionB;
  /// Позиция overlay'я на canvas-9:16 (0..1).
  final double x;
  final double y;
  final int votesA;
  final int votesB;
  /// -1 = не голосовал; 0 = A; 1 = B.
  final int myVote;

  const StoryPoll({
    required this.question,
    required this.optionA,
    required this.optionB,
    this.x = 0.1,
    this.y = 0.4,
    this.votesA = 0,
    this.votesB = 0,
    this.myVote = -1,
  });

  bool get hasVoted => myVote >= 0;
  int get totalVotes => votesA + votesB;
  double get percentA =>
      totalVotes == 0 ? 0 : (votesA / totalVotes * 100).roundToDouble();
  double get percentB =>
      totalVotes == 0 ? 0 : (votesB / totalVotes * 100).roundToDouble();

  factory StoryPoll.fromJson(Map<String, dynamic> j) => StoryPoll(
        question: j['question']?.toString() ?? '',
        optionA: j['option_a']?.toString() ?? '',
        optionB: j['option_b']?.toString() ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0.1,
        y: (j['y'] as num?)?.toDouble() ?? 0.4,
        votesA: (j['votes_a'] as num?)?.toInt() ?? 0,
        votesB: (j['votes_b'] as num?)?.toInt() ?? 0,
        myVote: (j['my_vote'] as num?)?.toInt() ?? -1,
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'option_a': optionA,
        'option_b': optionB,
        'x': x,
        'y': y,
      };

  StoryPoll copyWith({
    int? votesA,
    int? votesB,
    int? myVote,
  }) =>
      StoryPoll(
        question: question,
        optionA: optionA,
        optionB: optionB,
        x: x,
        y: y,
        votesA: votesA ?? this.votesA,
        votesB: votesB ?? this.votesB,
        myVote: myVote ?? this.myVote,
      );
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
