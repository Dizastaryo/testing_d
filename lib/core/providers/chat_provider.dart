import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import '../services/logger.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

// Chat models (kept inline since they were previously in mock_service).
// kind == 'direct' → otherUser != null, title/coverUrl пустые.
// kind == 'group'  → otherUser == null, заполнены title/coverUrl + participantsCount.
class Chat {
  final String id;
  final String kind; // 'direct' | 'group'
  final String title; // только для group
  final String coverUrl; // только для group
  final User? otherUser; // только для direct
  final int participantsCount; // только для group
  final String lastMessage;
  final String
      lastSenderUsername; // для group: префикс «X: ...» в last-сообщении
  final DateTime lastMessageAt;
  final int unreadCount;

  /// Закреплённое сообщение (sticky-banner на topе чата). nil = ничего не закреплено.
  final ReplyPreview? pinnedMessage;

  /// ID сбора, если этот group-чат является чатом сбора. null — обычный чат.
  final String? sborId;

  /// true если текущий пользователь — организатор сбора этого чата.
  final bool isOrganizer;

  /// Закреплён ли чат у текущего пользователя (хранится на сервере).
  final bool isPinned;

  /// Архивирован ли чат у текущего пользователя.
  final bool isArchived;

  /// Отключены ли уведомления для этого чата.
  final bool isMuted;

  const Chat({
    required this.id,
    this.kind = 'direct',
    this.title = '',
    this.coverUrl = '',
    this.otherUser,
    this.participantsCount = 0,
    required this.lastMessage,
    this.lastSenderUsername = '',
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.pinnedMessage,
    this.sborId,
    this.isOrganizer = false,
    this.isPinned = false,
    this.isArchived = false,
    this.isMuted = false,
  });

  bool get isGroup => kind == 'group';

  /// Display label: title для group, username для direct.
  String get displayLabel => isGroup ? title : (otherUser?.username ?? '');

  /// Immutable update. Чаще всего меняется otherUser presence или lastMessage.
  Chat copyWith({
    String? id,
    String? kind,
    String? title,
    String? coverUrl,
    User? otherUser,
    int? participantsCount,
    String? lastMessage,
    String? lastSenderUsername,
    DateTime? lastMessageAt,
    int? unreadCount,
    ReplyPreview? pinnedMessage,
    String? sborId,
    bool? isOrganizer,
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
  }) {
    return Chat(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      otherUser: otherUser ?? this.otherUser,
      participantsCount: participantsCount ?? this.participantsCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderUsername: lastSenderUsername ?? this.lastSenderUsername,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      sborId: sborId ?? this.sborId,
      isOrganizer: isOrganizer ?? this.isOrganizer,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final kind = (json['kind']?.toString().isNotEmpty ?? false)
        ? json['kind'].toString()
        : 'direct';
    final otherUserData = json['other_user'];
    User? other;
    if (otherUserData is Map<String, dynamic>) {
      other = User.fromJson(otherUserData);
    }
    if (kind == 'direct' && other == null) {
      throw FormatException('Chat.fromJson: direct chat без other_user');
    }
    return Chat(
      id: json['id']?.toString() ?? '',
      kind: kind,
      title: json['title']?.toString() ?? '',
      coverUrl: _absUrl(json['cover_url']?.toString()),
      otherUser: other,
      participantsCount: (json['participants_count'] ?? 0) as int,
      lastMessage: json['last_message']?.toString() ?? '',
      lastSenderUsername: json['last_sender_username']?.toString() ?? '',
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'].toString()) ??
              DateTime.now()
          : DateTime.now(),
      unreadCount: (json['unread_count'] ?? 0) as int,
      pinnedMessage: json['pinned_message'] is Map<String, dynamic>
          ? ReplyPreview.fromJson(
              json['pinned_message'] as Map<String, dynamic>)
          : null,
      sborId: json['sbor_id']?.toString(),
      isOrganizer: (json['is_organizer'] ?? false) as bool,
      isPinned: (json['is_pinned'] ?? false) as bool,
      isArchived: (json['archived'] ?? false) as bool,
      isMuted: (json['muted'] ?? false) as bool,
    );
  }
}

class AttachedPostShort {
  final String id;
  final String caption;
  final String mediaUrl;
  final String mediaType;
  final String thumbnailUrl;
  final String authorUsername;
  final String authorAvatar;

  const AttachedPostShort({
    required this.id,
    required this.caption,
    required this.mediaUrl,
    required this.mediaType,
    required this.thumbnailUrl,
    required this.authorUsername,
    required this.authorAvatar,
  });

  factory AttachedPostShort.fromJson(Map<String, dynamic> j) =>
      AttachedPostShort(
        id: j['id']?.toString() ?? '',
        caption: j['caption']?.toString() ?? '',
        mediaUrl: j['media_url']?.toString() ?? '',
        mediaType: j['media_type']?.toString() ?? '',
        thumbnailUrl: j['thumbnail_url']?.toString() ?? '',
        authorUsername: j['author_username']?.toString() ?? '',
        authorAvatar: j['author_avatar']?.toString() ?? '',
      );
}

/// Сжатое превью оригинального message'а для reply-bubble'я.
class ReplyPreview {
  final String id;
  final String senderId;
  final String senderUsername;
  final String text;
  final String kind;

  const ReplyPreview({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    required this.kind,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: j['id']?.toString() ?? '',
        senderId: j['sender_id']?.toString() ?? '',
        senderUsername: j['sender_username']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'text',
      );

  /// Краткое описание для UI: текст для kind=text, иначе тип ("фото"/"голос"/"пост").
  String shortLabel() {
    switch (kind) {
      case 'image':
        return '📷 Фото';
      case 'voice':
      case 'audio':
        return '🎙 Голосовое';
      case 'shared_post':
        return '📄 Пост';
      default:
        return text.isEmpty ? 'Сообщение' : text;
    }
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool isMe;
  final bool isRead;

  /// True когда сообщение доставлено хотя бы одному peer'у (CHAT-10.1).
  /// Computed на бэке как `delivered_count > 0`.
  final bool isDelivered;

  /// Per-recipient counts (CHAT-10.2). Для direct-чата recipientsCount=1.
  /// Для group: bubble рисует «X из N» когда `readCount < recipientsCount`.
  final int deliveredCount;
  final int readCount;
  final int recipientsCount;

  /// CHAT-11: момент когда сообщение исчезнет. null = вечно. Frontend
  /// рисует ⏱ countdown + auto-remove из local state по Timer'у.
  final DateTime? expiresAt;

  /// "text" (default), "shared_post", "image", "voice".
  final String kind;
  final AttachedPostShort? attachedPost;

  /// For kind="image"/"voice" — server-relative URL like `/uploads/...`.
  final String attachedMediaUrl;
  final String attachedMediaType;

  /// For kind="voice" — длительность аудио в секундах.
  final int mediaDurationSeconds;

  /// For kind="voice" — нормализованные сэмплы 0..1 (обычно ~48 точек) для
  /// прорисовки waveform'а в bubble без декодирования аудио клиентом.
  final List<double> waveform;

  /// Если это reply на другое сообщение — preview оригинала (text/username/kind).
  /// nil — обычное сообщение.
  final ReplyPreview? replyTo;

  /// Reaction counts per emoji aggregated by server. Empty when none.
  final Map<String, int> reactions;

  /// The emoji the *current user* placed on this message — empty when none.
  final String myReaction;

  /// Sender info (for group chats)
  final String senderName;
  final String senderUsername;
  final String senderAvatarUrl;

  /// True если сообщение мягко удалено для всех (WhatsApp-стиль).
  /// Фронт показывает «Сообщение удалено» вместо содержимого.
  final bool isDeletedForAll;

  /// Forwarding: имя отправителя оригинального сообщения.
  /// Пустая строка = не пересланное. Заполняется бэком (forwarded_from_sender)
  /// или на фронте при оптимистичном пересылании.
  final String forwardedFromSender;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.isMe = false,
    this.isRead = false,
    this.isDelivered = false,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.recipientsCount = 0,
    this.expiresAt,
    this.kind = 'text',
    this.attachedPost,
    this.attachedMediaUrl = '',
    this.attachedMediaType = '',
    this.mediaDurationSeconds = 0,
    this.waveform = const [],
    this.replyTo,
    this.reactions = const {},
    this.myReaction = '',
    this.senderName = '',
    this.senderUsername = '',
    this.senderAvatarUrl = '',
    this.isDeletedForAll = false,
    this.forwardedFromSender = '',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final ap = json['attached_post'];
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isMe: (json['is_me'] ?? false) as bool,
      isRead: (json['is_read'] ?? false) as bool,
      isDelivered: (json['is_delivered'] ?? false) as bool,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      recipientsCount: (json['recipients_count'] as num?)?.toInt() ?? 0,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      kind: json['kind']?.toString() ?? 'text',
      attachedPost:
          ap is Map<String, dynamic> ? AttachedPostShort.fromJson(ap) : null,
      attachedMediaUrl: json['attached_media_url']?.toString() ?? '',
      attachedMediaType: json['attached_media_type']?.toString() ?? '',
      mediaDurationSeconds:
          (json['media_duration_seconds'] as num?)?.toInt() ?? 0,
      waveform: json['waveform'] is List
          ? (json['waveform'] as List)
              .map((e) => (e is num) ? e.toDouble() : 0.0)
              .toList()
          : const [],
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? ReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      reactions: json['reactions'] is Map
          ? Map<String, int>.from(
              (json['reactions'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v is num) ? v.toInt() : 0),
              ),
            )
          : const {},
      myReaction: json['my_reaction']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      senderUsername: json['sender_username']?.toString() ?? '',
      senderAvatarUrl: _absUrl(json['sender_avatar_url']?.toString()),
      isDeletedForAll: (json['is_deleted_for_all'] ?? false) as bool,
      forwardedFromSender: json['forwarded_from_sender']?.toString() ?? '',
    );
  }

  ChatMessage copyWith({
    String? text,
    bool? isRead,
    bool? isDelivered,
    int? deliveredCount,
    int? readCount,
    int? recipientsCount,
    String? kind,
    AttachedPostShort? attachedPost,
    String? attachedMediaUrl,
    String? attachedMediaType,
    int? mediaDurationSeconds,
    List<double>? waveform,
    ReplyPreview? replyTo,
    Map<String, int>? reactions,
    String? myReaction,
    String? senderName,
    String? senderUsername,
    String? senderAvatarUrl,
    bool? isDeletedForAll,
    String? forwardedFromSender,
  }) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        senderId: senderId,
        text: text ?? this.text,
        createdAt: createdAt,
        isMe: isMe,
        isRead: isRead ?? this.isRead,
        isDelivered: isDelivered ?? this.isDelivered,
        deliveredCount: deliveredCount ?? this.deliveredCount,
        readCount: readCount ?? this.readCount,
        recipientsCount: recipientsCount ?? this.recipientsCount,
        expiresAt: expiresAt,
        kind: kind ?? this.kind,
        attachedPost: attachedPost ?? this.attachedPost,
        attachedMediaUrl: attachedMediaUrl ?? this.attachedMediaUrl,
        attachedMediaType: attachedMediaType ?? this.attachedMediaType,
        mediaDurationSeconds: mediaDurationSeconds ?? this.mediaDurationSeconds,
        waveform: waveform ?? this.waveform,
        replyTo: replyTo ?? this.replyTo,
        reactions: reactions ?? this.reactions,
        myReaction: myReaction ?? this.myReaction,
        senderName: senderName ?? this.senderName,
        senderUsername: senderUsername ?? this.senderUsername,
        senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
        isDeletedForAll: isDeletedForAll ?? this.isDeletedForAll,
        forwardedFromSender: forwardedFromSender ?? this.forwardedFromSender,
      );
}

class ChatListState {
  final List<Chat> chats;
  final bool isLoading;
  const ChatListState({this.chats = const [], this.isLoading = false});
  ChatListState copyWith({List<Chat>? chats, bool? isLoading}) => ChatListState(
      chats: chats ?? this.chats, isLoading: isLoading ?? this.isLoading);
}

class ChatListNotifier extends StateNotifier<ChatListState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  ChatListNotifier(this._api, this._ref) : super(const ChatListState()) {
    load();
    _listenRealtime();
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          // Любое из событий ниже инвалидирует превью чат-листа: новое
          // сообщение, добавление/удаление участников группы, создание новой
          // группы (где меня указали). Refetch один — получаем свежие
          // last_message, unread, kind, title, participants_count.
          const triggerEvents = {
            'chat.message',
            'chat.message.read',
            'chat.message.edited',
            'chat.group.joined',
            'chat.group.member.added',
            'chat.group.member.removed',
            'chat.pinned',
            'chat.message.deleted',
          };
          if (triggerEvents.contains(evt.type)) {
            load(silent: true);
            return;
          }
          // Обновление названия/обложки группы — мутируем локально без
          // полного рефетча чтобы не прыгал список.
          if (evt.type == 'chat.group.updated' && evt.payload is Map) {
            final p = (evt.payload as Map).cast<String, dynamic>();
            final chatId = p['chat_id']?.toString() ?? '';
            final title = p['title']?.toString() ?? '';
            final coverUrl = _absUrl(p['cover_url']?.toString());
            if (chatId.isEmpty) return;
            final updated = state.chats.map((c) {
              if (c.id != chatId) return c;
              return c.copyWith(title: title, coverUrl: coverUrl);
            }).toList();
            state = state.copyWith(chats: updated);
            return;
          }
          // user.presence — не рефетчим целиком, только мутируем
          // otherUser у direct-чатов где id совпадает.
          if (evt.type == 'user.presence' && evt.payload is Map) {
            final p = (evt.payload as Map).cast<String, dynamic>();
            final userId = p['user_id']?.toString() ?? '';
            if (userId.isEmpty) return;
            final isOnline = (p['is_online'] ?? false) as bool;
            final lastSeen = p['last_seen_at'] != null
                ? DateTime.tryParse(p['last_seen_at'].toString())
                : null;
            final updated = state.chats.map((chat) {
              if (chat.otherUser == null || chat.otherUser!.id != userId) {
                return chat;
              }
              return chat.copyWith(
                otherUser: chat.otherUser!.copyWith(
                  isOnline: isOnline,
                  lastSeenAt: lastSeen,
                ),
              );
            }).toList();
            state = state.copyWith(chats: updated);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiEndpoints.chats);
      final data = response.data['data'];
      if (data is List) {
        final chats =
            data.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();
        state = ChatListState(chats: chats);
      } else {
        state = const ChatListState(chats: []);
      }
    } catch (e, st) {
      appLog.error('[ChatListNotifier] load error', e, st);
      // Не стираем старый список при ошибке сети — пользователь видит кэш.
      state = state.copyWith(isLoading: false);
    }
  }

  /// Optimistically clears unread count for a chat (called when user opens it).
  void markChatRead(String chatId) {
    final updated = state.chats.map((c) {
      if (c.id != chatId) return c;
      return c.copyWith(unreadCount: 0);
    }).toList();
    state = state.copyWith(chats: updated);
  }

  /// Toggles pin-to-top for [chatId]. Optimistically updates local state
  /// and syncs with server. Returns new isPinned value.
  Future<bool> togglePin(String chatId) async {
    final prev = state.chats.firstWhere((c) => c.id == chatId,
        orElse: () => throw StateError('chat $chatId not found'));
    final newPinned = !prev.isPinned;
    // Optimistic update.
    final updated = state.chats.map((c) {
      if (c.id != chatId) return c;
      return c.copyWith(isPinned: newPinned);
    }).toList();
    // Re-sort: pinned first.
    updated.sort((a, b) {
      if (a.isPinned == b.isPinned) {
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      }
      return a.isPinned ? -1 : 1;
    });
    state = state.copyWith(chats: updated);
    try {
      await _api.put(ApiEndpoints.chatUserPin(chatId));
    } catch (e, st) {
      appLog.error('[ChatListNotifier] togglePin error', e, st);
      // Roll back.
      final rolled = state.chats.map((c) {
        if (c.id != chatId) return c;
        return c.copyWith(isPinned: prev.isPinned);
      }).toList();
      state = state.copyWith(chats: rolled);
      return prev.isPinned;
    }
    return newPinned;
  }

  /// Optimistically archives or unarchives [chatId] for current user.
  Future<void> archiveChat(String chatId, bool archived) async {
    final updated = state.chats.map((c) {
      if (c.id != chatId) return c;
      return c.copyWith(isArchived: archived);
    }).toList();
    state = state.copyWith(chats: updated);
    try {
      await _api.patch(ApiEndpoints.chatArchive(chatId), data: {'archived': archived});
    } catch (e, st) {
      appLog.error('[ChatListNotifier] archiveChat error', e, st);
      // Roll back.
      final rolled = state.chats.map((c) {
        if (c.id != chatId) return c;
        return c.copyWith(isArchived: !archived);
      }).toList();
      state = state.copyWith(chats: rolled);
    }
  }

  /// Optimistically mutes or unmutes notifications for [chatId].
  Future<void> muteChat(String chatId, bool muted) async {
    final updated = state.chats.map((c) {
      if (c.id != chatId) return c;
      return c.copyWith(isMuted: muted);
    }).toList();
    state = state.copyWith(chats: updated);
    try {
      await _api.patch(ApiEndpoints.chatMute(chatId), data: {'muted': muted});
    } catch (e, st) {
      appLog.error('[ChatListNotifier] muteChat error', e, st);
      // Roll back.
      final rolled = state.chats.map((c) {
        if (c.id != chatId) return c;
        return c.copyWith(isMuted: !muted);
      }).toList();
      state = state.copyWith(chats: rolled);
    }
  }

  /// Hides a chat from the list (delete for self for direct; leave for group).
  /// Removes the chat from local state immediately.
  Future<void> hideChat(
    String chatId, {
    bool isGroup = false,
    String? sborId,
    bool isOrganizer = false,
  }) async {
    // Optimistic remove.
    state = state.copyWith(
      chats: state.chats.where((c) => c.id != chatId).toList(),
    );
    try {
      if (isOrganizer && sborId != null) {
        // Организатор отменяет сбор → DELETE /sbory/:id
        await _api.delete(ApiEndpoints.cancelSbor(sborId));
      } else if (sborId != null) {
        // Участник покидает сбор → DELETE /sbory/:id/join
        await _api.delete(ApiEndpoints.leaveSbor(sborId));
      } else if (isGroup) {
        await _api.delete(ApiEndpoints.leaveGroupChat(chatId));
      } else {
        await _api.delete(ApiEndpoints.chatHide(chatId));
      }
    } catch (e, st) {
      appLog.error('[ChatListNotifier] hideChat error', e, st);
      // Reload to restore state on error.
      await load();
    }
  }

  /// Create or get a conversation with another user and return its ID.
  Future<String?> getOrCreateChat(String otherUserId) async {
    try {
      final response = await _api.post(
        ApiEndpoints.chats,
        data: {'user_id': otherUserId},
      );
      final id = response.data['data']?['id']?.toString();
      // Reload chat list after creating
      await load();
      return id;
    } catch (e, st) {
      appLog.error('[ChatListNotifier] getOrCreateChat error', e, st);
      return null;
    }
  }
}

class ChatMessagesState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool hasMore;
  final Chat? chat;
  final String? error;
  final bool loadOlderFailed;
  const ChatMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.hasMore = true,
    this.chat,
    this.error,
    this.loadOlderFailed = false,
  });
  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? hasMore,
    Chat? chat,
    String? error,
    bool? loadOlderFailed,
  }) =>
      ChatMessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        hasMore: hasMore ?? this.hasMore,
        chat: chat ?? this.chat,
        error: error ?? this.error,
        loadOlderFailed: loadOlderFailed ?? this.loadOlderFailed,
      );
}

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final String chatId;
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  ChatMessagesNotifier(this.chatId, this._api, this._ref)
      : super(const ChatMessagesState()) {
    load();
    _listenRealtime();
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          if (p['chat_id']?.toString() != chatId) return;

          if (evt.type == 'chat.message') {
            try {
              final msg = ChatMessage.fromJson(p);
              // Dedupe by id — server-bounce of own message is suppressed by
              // pushChatMessage (only peers get the WS event), but defensive.
              if (state.messages.any((m) => m.id == msg.id)) return;
              state = state.copyWith(messages: [...state.messages, msg]);
            } catch (e, st) {
              appLog.error('[ChatMessagesNotifier] parse ws msg', e, st);
            }
            return;
          }

          if (evt.type == 'chat.reaction') {
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            final raw = p['reactions'];
            final newCounts = raw is Map
                ? Map<String, int>.from(raw.map((k, v) =>
                    MapEntry(k.toString(), (v is num) ? v.toInt() : 0)))
                : <String, int>{};
            state = state.copyWith(
              messages: state.messages.map((m) {
                if (m.id != messageId) return m;
                // myReaction not affected — it's *current user's* reaction.
                // Server pushes only to peers, so for *us* this is always
                // someone else's change.
                return m.copyWith(reactions: newCounts);
              }).toList(),
            );
            return;
          }

          if (evt.type == 'chat.delivered') {
            // Peer's WS получил моё сообщение (CHAT-10.1 / CHAT-10.2).
            // Payload содержит свежие per-recipient counts — обновляем
            // их и isDelivered. В group-чате одно сообщение может прийти
            // несколько раз (от каждого online peer'а), counts будут
            // монотонно расти.
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            final dc = (p['delivered_count'] as num?)?.toInt() ?? 0;
            final rc = (p['read_count'] as num?)?.toInt() ?? 0;
            final rec = (p['recipients_count'] as num?)?.toInt() ?? 0;
            state = state.copyWith(
              messages: state.messages.map((m) {
                if (m.id != messageId || !m.isMe) return m;
                return m.copyWith(
                  isDelivered: true,
                  deliveredCount: dc > m.deliveredCount ? dc : m.deliveredCount,
                  readCount: rc > m.readCount ? rc : m.readCount,
                  recipientsCount: rec > 0 ? rec : m.recipientsCount,
                );
              }).toList(),
            );
            return;
          }

          if (evt.type == 'chat.read') {
            // Peer прочитал часть моих сообщений (CHAT-10.2).
            // Новый shape payload'а: `message_ids: [...]` + `counts_by_msg:
            // {msg_id: {delivered_count, read_count, recipients_count}}`.
            // Для backward compat fallback'имся на `reader_id` (старый
            // flow без counts) — флипаем isRead на все мои unread в этой
            // conversation.
            final readerId = p['reader_id']?.toString() ?? '';
            final ids =
                (p['message_ids'] as List?)?.map((e) => e.toString()).toSet() ??
                    <String>{};
            final countsByMsg = p['counts_by_msg'] is Map
                ? (p['counts_by_msg'] as Map).cast<String, dynamic>()
                : const <String, dynamic>{};

            final updated = state.messages.map((m) {
              if (!m.isMe || readerId == m.senderId) return m;
              // Новый flow: специфические message_id.
              if (ids.isNotEmpty) {
                if (!ids.contains(m.id)) return m;
                final cnt = countsByMsg[m.id];
                if (cnt is Map) {
                  final c = cnt.cast<String, dynamic>();
                  return m.copyWith(
                    isRead: true,
                    deliveredCount: (c['delivered_count'] as num?)?.toInt() ??
                        m.deliveredCount,
                    readCount:
                        (c['read_count'] as num?)?.toInt() ?? m.readCount,
                    recipientsCount: (c['recipients_count'] as num?)?.toInt() ??
                        m.recipientsCount,
                  );
                }
                return m.copyWith(isRead: true);
              }
              // Legacy flow (старые серверы без counts) — флипаем всё.
              if (!m.isRead) return m.copyWith(isRead: true);
              return m;
            }).toList();
            state = state.copyWith(messages: updated);
            return;
          }

          if (evt.type == 'chat.message.edited') {
            try {
              final msg = ChatMessage.fromJson(p);
              // Обновляем только текст — остальные поля (reactions, isRead и т.д.)
              // могут быть более актуальны в локальном state.
              state = state.copyWith(
                messages: state.messages.map((m) {
                  if (m.id != msg.id) return m;
                  return m.copyWith(text: msg.text);
                }).toList(),
              );
            } catch (e, st) {
              appLog.error('[ChatMessagesNotifier] parse ws edit', e, st);
            }
            return;
          }

          if (evt.type == 'chat.message.deleted') {
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            // WhatsApp-style: show "Сообщение удалено" instead of disappearing.
            // forSelf (scope=self) deletions from our own device arrive via
            // removeLocally(); peer-side WS always means "deleted for all".
            markDeletedForAll(messageId);
            return;
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  static const _pageSize = 50;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(
        ApiEndpoints.chatMessages(chatId),
        queryParameters: {'limit': _pageSize, 'offset': 0},
      );
      final data = response.data['data'];
      if (data is List) {
        final messages = data
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        state = ChatMessagesState(
          messages: messages,
          hasMore: messages.length >= _pageSize,
        );
      } else {
        state = const ChatMessagesState(messages: [], hasMore: false);
      }
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] load error', e, st);
      state = ChatMessagesState(error: e.toString());
    }
  }

  Future<void> loadOlderMessages() async {
    if (state.isLoadingOlder || !state.hasMore) return;
    state = state.copyWith(isLoadingOlder: true, loadOlderFailed: false);
    try {
      final response = await _api.get(
        ApiEndpoints.chatMessages(chatId),
        queryParameters: {
          'limit': _pageSize,
          'offset': state.messages.length,
        },
      );
      final data = response.data['data'];
      if (data is List) {
        final older = data
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(
          messages: [...older, ...state.messages],
          isLoadingOlder: false,
          hasMore: older.length >= _pageSize,
        );
      } else {
        state = state.copyWith(isLoadingOlder: false, hasMore: false);
      }
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] loadOlderMessages error', e, st);
      state = state.copyWith(isLoadingOlder: false, loadOlderFailed: true);
    }
  }

  /// Локальное удаление сообщения из state (CHAT-11). Вызывается из bubble
  /// когда Timer выявил что сообщение expired (даже до того как janitor
  /// проснулся и удалил из БД). На refetch'ах список приедет уже без него
  /// — GetMessages фильтрует expired в SQL.
  void removeMessageLocally(String messageId) {
    if (!state.messages.any((m) => m.id == messageId)) return;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  Future<void> sendMessage(
    String text, {
    String? attachedPostId,
    String? attachedMediaUrl,
    String? attachedMediaType,
    int mediaDurationSeconds = 0,
    List<double> waveform = const [],
    ReplyPreview? replyTo,
    int expiresInSeconds = 0,
    bool rethrowOnError = false,
    String? forwardedFromMessageId,
    String forwardedFromSender = '',
  }) async {
    final hasMedia = attachedMediaUrl != null && attachedMediaUrl.isNotEmpty;
    // Derive kind from attachedMediaType for correct optimistic bubble.
    final kind = attachedPostId != null
        ? 'shared_post'
        : hasMedia
            ? switch (attachedMediaType) {
                'audio' => 'voice',
                'video_note' => 'video_note',
                'video' => 'video',
                _ => 'image',
              }
            : 'text';

    // Optimistic UI: add message locally (no preview yet — server fills it).
    final myId = _ref.read(authProvider).user?.id ?? 'me';
    final optimistic = ChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: myId,
      text: text,
      createdAt: DateTime.now(),
      isMe: true,
      kind: kind,
      attachedMediaUrl: attachedMediaUrl ?? '',
      attachedMediaType: attachedMediaType ?? '',
      mediaDurationSeconds: mediaDurationSeconds,
      waveform: waveform,
      replyTo: replyTo,
      forwardedFromSender: forwardedFromSender,
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);

    try {
      final resp = await _api.post(
        ApiEndpoints.chatMessages(chatId),
        data: {
          'text': text,
          if (attachedPostId != null) 'attached_post_id': attachedPostId,
          if (mediaDurationSeconds > 0)
            'media_duration_seconds': mediaDurationSeconds,
          if (waveform.isNotEmpty) 'waveform': waveform,
          if (replyTo != null) 'reply_to_message_id': replyTo.id,
          if (hasMedia) 'attached_media_url': attachedMediaUrl,
          if (hasMedia) 'attached_media_type': attachedMediaType ?? 'image',
          if (expiresInSeconds > 0) 'expires_in_seconds': expiresInSeconds,
          if (forwardedFromMessageId != null)
            'forwarded_from_message_id': forwardedFromMessageId,
          if (forwardedFromSender.isNotEmpty)
            'forwarded_from_sender': forwardedFromSender,
        },
      );
      // Replace the optimistic message with the real one from server
      // (real ID, post preview, expiresAt, etc.) — no full reload needed.
      final msgData = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data']
          : resp.data;
      if (msgData is Map<String, dynamic>) {
        final real = ChatMessage.fromJson(msgData);
        state = state.copyWith(
          messages: state.messages
              .map((m) => m.id == optimistic.id ? real : m)
              .toList(),
        );
      }
      // Update chat-list preview (last_message, order).
      // WS chat.message only fires for peers, so we refresh manually.
      _ref.read(chatListProvider.notifier).load();
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] sendMessage error', e, st);
      // Roll back optimistic message so it doesn't appear as sent forever.
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != optimistic.id).toList(),
      );
      if (rethrowOnError) rethrow;
    }
  }

  Future<void> markRead() async {
    _ref.read(chatListProvider.notifier).markChatRead(chatId);
    try {
      await _api.put(ApiEndpoints.chatRead(chatId));
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] markRead error', e, st);
    }
  }

  /// Optimistic local-only removal — для delete-flow в UI. API DELETE
  /// зовёт сам экран; на success WS event прилетит и подтвердит, на error
  /// экран вызывает [restoreMessages] чтобы откатить.
  void removeLocally(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  /// Восстановить полный список (используется для rollback delete).
  void restoreMessages(List<ChatMessage> snapshot) {
    state = state.copyWith(messages: snapshot);
  }

  /// Оптимистично помечает сообщение как «удалённое для всех» (WhatsApp-стиль).
  /// Сообщение остаётся в списке, но отображается как «Сообщение удалено».
  void markDeletedForAll(String messageId) {
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id != messageId) return m;
        return ChatMessage(
          id: m.id,
          chatId: m.chatId,
          senderId: m.senderId,
          text: '',
          createdAt: m.createdAt,
          isMe: m.isMe,
          isRead: m.isRead,
          isDelivered: m.isDelivered,
          deliveredCount: m.deliveredCount,
          readCount: m.readCount,
          recipientsCount: m.recipientsCount,
          kind: 'deleted',
          senderName: m.senderName,
          senderUsername: m.senderUsername,
          senderAvatarUrl: m.senderAvatarUrl,
          isDeletedForAll: true,
        );
      }).toList(),
    );
  }

  /// Редактирует текст сообщения. Оптимистично обновляет локально,
  /// откатывает при ошибке.
  Future<void> editMessage(String messageId, String newText) async {
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final original = state.messages[idx];
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, idx),
        original.copyWith(text: newText),
        ...state.messages.sublist(idx + 1),
      ],
    );
    try {
      await _api.patch(
        ApiEndpoints.chatMessageEdit(chatId, messageId),
        data: {'text': newText},
      );
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] editMessage error', e, st);
      final i = state.messages.indexWhere((m) => m.id == messageId);
      if (i >= 0) {
        state = state.copyWith(
          messages: [
            ...state.messages.sublist(0, i),
            original,
            ...state.messages.sublist(i + 1),
          ],
        );
      }
      rethrow;
    }
  }

  /// Toggle the current user's reaction on a message. If `emoji` matches the
  /// existing one — sends DELETE; otherwise POST with the new emoji
  /// (server upserts, so switching emojis is one call).
  Future<void> toggleReaction(String messageId, String emoji) async {
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final original = state.messages[idx];
    final isSame = original.myReaction == emoji;

    // Optimistic: apply target shape locally so UI updates instantly.
    final newCounts = Map<String, int>.from(original.reactions);
    if (original.myReaction.isNotEmpty) {
      newCounts[original.myReaction] =
          (newCounts[original.myReaction] ?? 1) - 1;
      if ((newCounts[original.myReaction] ?? 0) <= 0) {
        newCounts.remove(original.myReaction);
      }
    }
    final newMine = isSame ? '' : emoji;
    if (newMine.isNotEmpty) {
      newCounts[newMine] = (newCounts[newMine] ?? 0) + 1;
    }
    state = state.copyWith(
      messages: [
        ...state.messages.sublist(0, idx),
        original.copyWith(reactions: newCounts, myReaction: newMine),
        ...state.messages.sublist(idx + 1),
      ],
    );

    try {
      if (isSame) {
        await _api.delete(ApiEndpoints.chatMessageReact(messageId));
      } else {
        await _api.post(ApiEndpoints.chatMessageReact(messageId),
            data: {'emoji': emoji});
      }
    } catch (e, st) {
      appLog.error('[ChatMessagesNotifier] toggleReaction error', e, st);
      // Roll back to previous shape on error.
      final i = state.messages.indexWhere((m) => m.id == messageId);
      if (i >= 0) {
        state = state.copyWith(
          messages: [
            ...state.messages.sublist(0, i),
            original,
            ...state.messages.sublist(i + 1),
          ],
        );
      }
    }
  }
}

/// Один typer в чате (CHAT-2.1/2.2). Хранит username (опционально, может
/// прийти пустым если бэк не резолвнул) + lastSeenAt для TTL GC.
class TypingUser {
  final String userId;
  final String username;
  final DateTime lastSeenAt;
  const TypingUser({
    required this.userId,
    required this.username,
    required this.lastSeenAt,
  });
}

/// Snapshot активно-печатающих в этом чате (CHAT-2.2 multi-typer).
/// `users` ключ — user_id; entries TTL-protected на 4с через периодический GC.
///
/// Helpers рендерят правильную русскую плюрализацию для bubble-header:
///   1 typer  → «@user печатает…»
///   2 typer'а → «@a и @b печатают…»
///   3+ typer'ов → «@a, @b и ещё N печатают…»
class TypingState {
  final Map<String, TypingUser> users;
  const TypingState({this.users = const {}});

  bool get isActive => users.isNotEmpty;

  /// Backward-compat для старого `state.userId` (если когда-нибудь.
  /// Возвращает first key или null. Новый код должен использовать `users`.
  String? get userId => users.isEmpty ? null : users.keys.first;

  /// Готовый display-label («@a, @b и ещё N печатают…»). null если никто.
  /// `fallbackLabel` — что показывать когда username не пришёл (анон typer).
  String? buildLabel({String fallbackLabel = 'кто-то'}) {
    if (users.isEmpty) return null;
    // Сортируем по lastSeenAt DESC чтобы newest typer'ы попали в front.
    final sorted = users.values.toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    String nameOf(TypingUser u) =>
        u.username.isNotEmpty ? '@${u.username}' : fallbackLabel;
    final n = sorted.length;
    final verb = n == 1 ? 'печатает' : 'печатают';
    if (n == 1) {
      return '${nameOf(sorted[0])} $verb…';
    }
    if (n == 2) {
      return '${nameOf(sorted[0])} и ${nameOf(sorted[1])} $verb…';
    }
    final extra = n - 2;
    return '${nameOf(sorted[0])}, ${nameOf(sorted[1])} и ещё $extra $verb…';
  }
}

class _TypingNotifier extends StateNotifier<TypingState> {
  static const _typingTtl = Duration(seconds: 4);
  final String chatId;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _sub;
  Timer? _gc;

  _TypingNotifier(this.chatId, this._ref) : super(const TypingState()) {
    _sub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'chat.typing' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          if (p['chat_id']?.toString() != chatId) return;
          final uid = p['user_id']?.toString() ?? '';
          if (uid.isEmpty) return;
          final uname = p['username']?.toString() ?? '';
          final next = Map<String, TypingUser>.from(state.users);
          next[uid] = TypingUser(
            userId: uid,
            username: uname,
            lastSeenAt: DateTime.now(),
          );
          state = TypingState(users: next);
        });
      },
    );
    // GC раз в секунду — удаляет TypingUser'ов которые перестали слать
    // typing-events. Single timer для всех users; cheap.
    _gc = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.users.isEmpty) return;
      final cutoff = DateTime.now().subtract(_typingTtl);
      final filtered = <String, TypingUser>{};
      var changed = false;
      state.users.forEach((k, v) {
        if (v.lastSeenAt.isAfter(cutoff)) {
          filtered[k] = v;
        } else {
          changed = true;
        }
      });
      if (changed) state = TypingState(users: filtered);
    });
  }

  @override
  void dispose() {
    _gc?.cancel();
    _sub?.close();
    super.dispose();
  }
}

final typingProvider =
    StateNotifierProvider.family<_TypingNotifier, TypingState, String>(
  (ref, chatId) => _TypingNotifier(chatId, ref),
);

/// Тот же сигнал что [typingProvider], но в виде одного `Map<chatId, lastAt>`
/// для chat-list. Слушает realtime ОДИН раз и обновляет карту, а tiles
/// берут через `.select((m) => m.containsKey(chatId))` — O(1) на тайл вместо
/// O(N) listener'ов как было бы с family-провайдером.
class _TypingChatsNotifier extends StateNotifier<Map<String, DateTime>> {
  static const _ttl = Duration(seconds: 4);
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _sub;
  Timer? _gc;

  _TypingChatsNotifier(this._ref) : super(const {}) {
    _sub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (_, next) {
        next.whenData((evt) {
          if (evt.type != 'chat.typing' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final chatId = p['chat_id']?.toString() ?? '';
          if (chatId.isEmpty) return;
          state = {...state, chatId: DateTime.now()};
        });
      },
    );
    // GC раз в секунду: убираем устаревшие записи. Без этого даже если peer
    // перестал печатать, карта продолжала бы хранить запись до перезапуска.
    _gc = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isEmpty) return;
      final cutoff = DateTime.now().subtract(_ttl);
      var changed = false;
      final next = <String, DateTime>{};
      state.forEach((k, v) {
        if (v.isAfter(cutoff)) {
          next[k] = v;
        } else {
          changed = true;
        }
      });
      if (changed) state = next;
    });
  }

  @override
  void dispose() {
    _gc?.cancel();
    _sub?.close();
    super.dispose();
  }
}

final typingChatsProvider =
    StateNotifierProvider<_TypingChatsNotifier, Map<String, DateTime>>(
  (ref) => _TypingChatsNotifier(ref),
);

final chatListProvider =
    StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ChatListNotifier(api, ref);
});

final chatMessagesProvider = StateNotifierProvider.family<ChatMessagesNotifier,
    ChatMessagesState, String>((ref, chatId) {
  final api = ref.watch(apiClientProvider);
  return ChatMessagesNotifier(chatId, api, ref);
});

/// Queue для auto-next voice playback (CHAT-7). Когда один VoiceBubble
/// завершил воспроизведение, он находит следующий voice-message в чате
/// и записывает его id сюда. Соответствующий VoiceBubble слушает provider
/// через `ref.listenManual` и на match — стартует play автоматически.
///
/// Используется как «one-shot» сигнал: после play queue сбрасывается в null,
/// чтобы не залип на одном id (иначе при rebuild'е bubble захочет начать
/// заново).
final voiceAutoPlayQueueProvider = StateProvider<String?>((_) => null);

/// Coordinator для voice playback (CHAT-6.1). Хранит id voice'а который
/// сейчас играет — других voice-bubble'ов слушают и pause'ятся когда
/// значение меняется на не-их id. null = никто не играет.
///
/// Преимущества Riverpod-провайдера vs static singleton: автоматический
/// cleanup при logout, легко тестировать, race-safe через notifier.
final currentlyPlayingVoiceProvider = StateProvider<String?>((_) => null);

/// Session-only set прослушанных voice-message id'шников (CHAT-7.1).
/// Auto-next loop пропускает messageId которые уже здесь. При рестарте
/// приложения set очищается (live-session трекинг, без backend-persist).
/// Если когда-нибудь надо persist — переехать на колонку
/// `messages.voice_listened_by UUID[]` (отдельная задача).
final listenedVoiceIdsProvider = StateProvider<Set<String>>((_) => const {});
