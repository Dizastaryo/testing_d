import 'user.dart';

class Comment {
  final String id;
  final String postId;
  final User author;
  final String text;
  final int likesCount;
  final bool isLiked;
  final String? parentId;
  final List<Comment> replies;
  final int repliesCount;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.text,
    this.likesCount = 0,
    this.isLiked = false,
    this.parentId,
    this.replies = const [],
    this.repliesCount = 0,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final repliesList = (json['replies'] as List?)
            ?.map((r) => Comment.fromJson(r as Map<String, dynamic>))
            .toList() ??
        [];

    return Comment(
      id: json['id']?.toString() ?? '',
      postId: json['post_id']?.toString() ?? '',
      author: User.fromJson(json['author'] as Map<String, dynamic>? ?? {}),
      text: json['text']?.toString() ?? '',
      // BUG-20: safe-cast через num? — backend BIGINT может прийти как
      // double если значение big enough; `as int` бы крашнул.
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      isLiked: (json['is_liked'] as bool?) ?? false,
      parentId: json['parent_id']?.toString(),
      replies: repliesList,
      repliesCount: (json['replies_count'] as num?)?.toInt() ?? repliesList.length,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'author': author.toJson(),
    'text': text,
    'likes_count': likesCount,
    'is_liked': isLiked,
    'parent_id': parentId,
    'replies': replies.map((r) => r.toJson()).toList(),
    'replies_count': repliesCount,
    'created_at': createdAt.toIso8601String(),
  };

  Comment copyWith({
    int? likesCount,
    bool? isLiked,
    List<Comment>? replies,
    int? repliesCount,
  }) {
    return Comment(
      id: id,
      postId: postId,
      author: author,
      text: text,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      parentId: parentId,
      replies: replies ?? this.replies,
      repliesCount: repliesCount ?? this.repliesCount,
      createdAt: createdAt,
    );
  }

}
