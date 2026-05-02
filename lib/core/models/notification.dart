import 'user.dart';

enum NotificationType {
  like,
  comment,
  follow,
  mention,
  reply,
  postTag,
}

class AppNotification {
  final String id;
  final NotificationType type;
  final User fromUser;
  final String? postId;
  final String? postThumbnailUrl;
  final String? commentText;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.fromUser,
    this.postId,
    this.postThumbnailUrl,
    this.commentText,
    this.isRead = false,
    required this.createdAt,
  });

  String get message {
    switch (type) {
      case NotificationType.like:
        return 'нравится ваше фото.';
      case NotificationType.comment:
        return commentText != null
            ? 'прокомментировал(а): $commentText'
            : 'прокомментировал(а) ваше фото.';
      case NotificationType.follow:
        return 'подписался(-ась) на вас.';
      case NotificationType.mention:
        return 'упомянул(а) вас в комментарии.';
      case NotificationType.reply:
        return commentText != null
            ? 'ответил(а): $commentText'
            : 'ответил(а) на ваш комментарий.';
      case NotificationType.postTag:
        return 'отметил(а) вас в публикации.';
    }
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: _parseType(json['type']?.toString()),
      fromUser: User.fromJson(json['from_user'] as Map<String, dynamic>? ?? {}),
      postId: json['post_id']?.toString(),
      postThumbnailUrl: json['post_thumbnail_url']?.toString(),
      commentText: json['comment_text']?.toString(),
      isRead: (json['is_read'] ?? false) as bool,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static NotificationType _parseType(String? type) {
    switch (type) {
      case 'like':
        return NotificationType.like;
      case 'comment':
        return NotificationType.comment;
      case 'follow':
        return NotificationType.follow;
      case 'mention':
        return NotificationType.mention;
      case 'reply':
        return NotificationType.reply;
      case 'post_tag':
        return NotificationType.postTag;
      default:
        return NotificationType.like;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'from_user': fromUser.toJson(),
    'post_id': postId,
    'post_thumbnail_url': postThumbnailUrl,
    'comment_text': commentText,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
  };

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      fromUser: fromUser,
      postId: postId,
      postThumbnailUrl: postThumbnailUrl,
      commentText: commentText,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

}
