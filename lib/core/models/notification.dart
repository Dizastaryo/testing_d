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
  /// Сколько ЕЩЁ юзеров присоединились к этому действию помимо fromUser.
  /// Например, 99 = «лайкнули User и ещё 99 человек». 0 = одиночная нотификация.
  final int othersCount;
  /// Превью аватарок других юзеров батча (max 3). Бэк возвращает UserShort'ы;
  /// здесь они UserShort из models/user.dart (re-exported). Когда othersCount=0,
  /// список всегда пустой.
  final List<UserShort> otherUsers;
  /// UUID комментария — для deep-link'а к конкретному комментарию на /post/:id.
  /// Заполняется бэком только для type=comment/reply/mention.
  final String? commentId;

  const AppNotification({
    required this.id,
    required this.type,
    required this.fromUser,
    this.postId,
    this.postThumbnailUrl,
    this.commentText,
    this.isRead = false,
    required this.createdAt,
    this.othersCount = 0,
    this.otherUsers = const [],
    this.commentId,
  });

  /// Текст после юзернейма (юзернейм рендерится отдельным жирным TextSpan'ом
  /// в notifications_screen). При othersCount > 0 — батч-фраза с глаголом
  /// множ. числа и человек/человека/человек по русскому падежу.
  String get message {
    if (othersCount > 0) {
      final n = othersCount;
      final ppl = _peopleWord(n);
      switch (type) {
        case NotificationType.like:
          return 'и ещё $n $ppl поставили лайк.';
        case NotificationType.comment:
          return 'и ещё $n $ppl прокомментировали.';
        case NotificationType.reply:
          return 'и ещё $n $ppl ответили.';
        case NotificationType.postTag:
          return 'и ещё $n $ppl отметили вас.';
        case NotificationType.follow:
        case NotificationType.mention:
          break; // эти типы backend не батчит — fallthrough к single-форме
      }
    }
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

  /// «человек» / «человека» / «человек» — русское склонение для числовых
  /// окончаний 1, 2-4, 5+ (а также особое правило для 11-14).
  static String _peopleWord(int n) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return 'человек';
    if (mod10 == 1) return 'человек';
    if (mod10 >= 2 && mod10 <= 4) return 'человека';
    return 'человек';
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
      othersCount: (json['others_count'] ?? 0) as int,
      otherUsers: (json['other_users'] is List)
          ? (json['other_users'] as List)
              .whereType<Map<String, dynamic>>()
              .map(UserShort.fromJson)
              .toList()
          : const [],
      commentId: json['comment_id']?.toString(),
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
    'others_count': othersCount,
    'other_users': otherUsers.map((u) => {
          'id': u.id,
          'username': u.username,
          'full_name': u.fullName,
          'avatar_url': u.avatarUrl,
          'is_verified': u.isVerified,
        }).toList(),
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
      othersCount: othersCount,
      otherUsers: otherUsers,
      commentId: commentId,
    );
  }

}
