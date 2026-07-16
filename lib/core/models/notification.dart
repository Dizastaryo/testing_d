import 'user.dart';

enum NotificationType {
  like,
  comment,
  follow,
  mention,
  reply,
  postTag,
  storyLike,
  missedCall,
  scannerLike,
  coin,
  spark,
  accessRequest,
  accessAccepted,
  pairPrompt,
  pairConfirmed,
  sborRequest,
  sborApproved,
  sborRejected,
  sborCancelled,
  // Неизвестный/будущий тип с бэка. Раньше _parseType по умолчанию отдавал
  // .like → чужие типы (missed_call, access_*, sbor_*) рендерились как «лайк»
  // и тап вёл в никуда. Теперь неизвестное честно падает сюда: показываем
  // серверный message как есть, навигацию не строим.
  unknown,
}

class AppNotification {
  final String id;
  final NotificationType type;
  final User fromUser;
  /// entity_id с бэка (post_id для social-типов, sbor_id для sbor-типов,
  /// request_id для access и т.д.). Раньше модель читала несуществующий
  /// `post_id` → всегда null, и тап по уведомлению никуда не вёл.
  final String? entityId;
  /// entity_type с бэка: "post" | "comment" | "story" | "sbor" |
  /// "access_request" | "follow_request" | ... Определяет навигацию.
  final String? entityType;
  /// Полностью готовый текст уведомления с сервера (`message`). Для sbor/
  /// access/unknown-типов клиент не может восстановить осмысленный текст
  /// (в нём имя сбора и т.п.), поэтому берём серверный.
  final String? serverMessage;
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
    this.entityId,
    this.entityType,
    this.serverMessage,
    this.postThumbnailUrl,
    this.commentText,
    this.isRead = false,
    required this.createdAt,
    this.othersCount = 0,
    this.otherUsers = const [],
    this.commentId,
  });

  /// ID поста для навигации на /post/:id. Есть только когда уведомление
  /// привязано к посту (entity_type == 'post': лайк/коммент/ответ/упоминание).
  String? get postId => entityType == 'post' ? entityId : null;

  /// ID сбора для навигации на /sbory/:id (sbor-уведомления).
  String? get sborId => entityType == 'sbor' ? entityId : null;

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
        case NotificationType.storyLike:
          return 'и ещё $n $ppl лайкнули вашу историю.';
        default:
          break; // остальные типы backend не батчит — fallthrough к single-форме
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
      case NotificationType.storyLike:
        return 'лайкнул(а) вашу историю.';
      case NotificationType.missedCall:
        return 'пропущенный звонок.';
      case NotificationType.scannerLike:
        return 'лайкнул(а) тебя в сканере.';
      case NotificationType.coin:
        return 'подарил(а) тебе монету харизмы.';
      case NotificationType.spark:
        return 'отправил(а) тебе Spark 🔥';
      case NotificationType.accessRequest:
        return 'запросил(а) доступ к переписке.';
      case NotificationType.accessAccepted:
        return 'открыл(а) вам доступ к переписке.';
      case NotificationType.pairPrompt:
        return 'Хотите стать парой? 🔥🔥';
      case NotificationType.pairConfirmed:
        return 'теперь вы пара 🔥🔥';
      case NotificationType.sborRequest:
      case NotificationType.sborApproved:
      case NotificationType.sborRejected:
      case NotificationType.sborCancelled:
      case NotificationType.unknown:
        // Для этих типов серверный message содержит имя сбора / детали —
        // клиент не может его восстановить, берём как есть.
        return serverMessage?.trim().isNotEmpty == true
            ? serverMessage!.trim()
            : _sborFallback(type);
    }
  }

  static String _sborFallback(NotificationType type) {
    switch (type) {
      case NotificationType.sborRequest:
        return 'подал(а) заявку в ваш сбор.';
      case NotificationType.sborApproved:
        return 'принял(а) вашу заявку в сбор.';
      case NotificationType.sborRejected:
        return 'отклонил(а) вашу заявку в сбор.';
      case NotificationType.sborCancelled:
        return 'отменил(а) сбор.';
      default:
        return 'новое уведомление.';
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
      entityId: json['entity_id']?.toString(),
      entityType: json['entity_type']?.toString(),
      serverMessage: json['message']?.toString(),
      postThumbnailUrl: json['post_thumbnail_url']?.toString(),
      commentText: json['comment_text']?.toString(),
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      // BUG-20: num? для счётчиков, не int — защита от BIGINT/double.
      othersCount: (json['others_count'] as num?)?.toInt() ?? 0,
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
      // Бэк шлёт 'comment_reply' (domain.NotificationTypeCommentReply), а не
      // 'reply' — раньше это не мэтчилось и падало в default(.like).
      case 'comment_reply':
      case 'reply':
        return NotificationType.reply;
      case 'post_tag':
        return NotificationType.postTag;
      case 'story_like':
        return NotificationType.storyLike;
      case 'missed_call':
        return NotificationType.missedCall;
      case 'scanner_like':
        return NotificationType.scannerLike;
      case 'coin':
        return NotificationType.coin;
      case 'spark':
        return NotificationType.spark;
      case 'access_request':
        return NotificationType.accessRequest;
      case 'access_accepted':
        return NotificationType.accessAccepted;
      case 'pair_prompt':
        return NotificationType.pairPrompt;
      case 'pair_confirmed':
        return NotificationType.pairConfirmed;
      case 'sbor_request':
        return NotificationType.sborRequest;
      case 'sbor_approved':
        return NotificationType.sborApproved;
      case 'sbor_rejected':
        return NotificationType.sborRejected;
      case 'sbor_cancelled':
        return NotificationType.sborCancelled;
      default:
        return NotificationType.unknown;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'from_user': fromUser.toJson(),
    'entity_id': entityId,
    'entity_type': entityType,
    'message': serverMessage,
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
    'comment_id': commentId,
  };

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      fromUser: fromUser,
      entityId: entityId,
      entityType: entityType,
      serverMessage: serverMessage,
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
