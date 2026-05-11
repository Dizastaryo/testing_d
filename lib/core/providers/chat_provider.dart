import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import 'realtime_provider.dart';

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
  final String lastSenderUsername; // для group: префикс «X: ...» в last-сообщении
  final DateTime lastMessageAt;
  final int unreadCount;
  /// Закреплённое сообщение (sticky-banner на topе чата). nil = ничего не закреплено.
  final ReplyPreview? pinnedMessage;

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
      coverUrl: json['cover_url']?.toString() ?? '',
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
  /// True когда сообщение реально доставлено в WS хотя бы одному peer'у
  /// (CHAT-10.1). Промежуточное состояние между `sent` (✓ серая) и `read`
  /// (✓✓ orange) — отображается ✓✓ серая. Поле computed на бэке как
  /// `delivered_at IS NOT NULL`.
  final bool isDelivered;
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

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.isMe = false,
    this.isRead = false,
    this.isDelivered = false,
    this.kind = 'text',
    this.attachedPost,
    this.attachedMediaUrl = '',
    this.attachedMediaType = '',
    this.mediaDurationSeconds = 0,
    this.waveform = const [],
    this.replyTo,
    this.reactions = const {},
    this.myReaction = '',
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
      kind: json['kind']?.toString() ?? 'text',
      attachedPost: ap is Map<String, dynamic>
          ? AttachedPostShort.fromJson(ap)
          : null,
      attachedMediaUrl: json['attached_media_url']?.toString() ?? '',
      attachedMediaType: json['attached_media_type']?.toString() ?? '',
      mediaDurationSeconds:
          (json['media_duration_seconds'] as num?)?.toInt() ?? 0,
      waveform: json['waveform'] is List
          ? (json['waveform'] as List)
              .map((e) => (e as num).toDouble())
              .toList()
          : const [],
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? ReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
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

  ChatMessage copyWith({
    bool? isRead,
    bool? isDelivered,
    Map<String, int>? reactions,
    String? myReaction,
  }) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        senderId: senderId,
        text: text,
        createdAt: createdAt,
        isMe: isMe,
        isRead: isRead ?? this.isRead,
        isDelivered: isDelivered ?? this.isDelivered,
        kind: kind,
        attachedPost: attachedPost,
        attachedMediaUrl: attachedMediaUrl,
        attachedMediaType: attachedMediaType,
        reactions: reactions ?? this.reactions,
        myReaction: myReaction ?? this.myReaction,
      );
}

class ChatListState {
  final List<Chat> chats;
  final bool isLoading;
  const ChatListState({this.chats = const [], this.isLoading = false});
  ChatListState copyWith({List<Chat>? chats, bool? isLoading}) =>
      ChatListState(chats: chats ?? this.chats, isLoading: isLoading ?? this.isLoading);
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
            'chat.group.joined',
            'chat.group.member.added',
            'chat.group.member.removed',
            'chat.pinned',
            'chat.message.deleted',
          };
          if (triggerEvents.contains(evt.type)) {
            load();
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

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiEndpoints.chats);
      final data = response.data['data'];
      if (data is List) {
        final chats = data
            .map((e) => Chat.fromJson(e as Map<String, dynamic>))
            .toList();
        state = ChatListState(chats: chats);
      } else {
        state = const ChatListState(chats: []);
      }
    } catch (e) {
      debugPrint('[ChatListNotifier] load error: $e');
      state = const ChatListState(chats: []);
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
    } catch (e) {
      debugPrint('[ChatListNotifier] getOrCreateChat error: $e');
      return null;
    }
  }
}

class ChatMessagesState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final Chat? chat;
  const ChatMessagesState({this.messages = const [], this.isLoading = false, this.chat});
  ChatMessagesState copyWith({List<ChatMessage>? messages, bool? isLoading, Chat? chat}) =>
      ChatMessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        chat: chat ?? this.chat,
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
            } catch (e) {
              debugPrint('[ChatMessagesNotifier] parse ws msg: $e');
            }
            return;
          }

          if (evt.type == 'chat.reaction') {
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            final raw = p['reactions'];
            final newCounts = raw is Map
                ? Map<String, int>.from(raw.map(
                    (k, v) => MapEntry(k.toString(), (v as num).toInt())))
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
            // Peer's WS получил моё сообщение (но ещё не открыл чат).
            // Flip isDelivered=true → checkmark ✓ → ✓✓ серый (intermediate
            // state перед read). Backend шлёт только sender'у в ChatService.
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            state = state.copyWith(
              messages: state.messages.map((m) {
                if (m.id != messageId || !m.isMe || m.isDelivered) return m;
                return m.copyWith(isDelivered: true);
              }).toList(),
            );
            return;
          }

          if (evt.type == 'chat.read') {
            // Peer just read the conversation — flip my outgoing messages
            // to is_read so the checkmark turns accent (✓ → ✓✓) without a
            // refresh. See _MessageBubble in chat_screen.dart for rendering.
            final readerId = p['reader_id']?.toString() ?? '';
            final updated = state.messages.map((m) {
              // Only flip messages I sent (m.isMe), and only if the reader
              // is *not* me (avoid no-op echoes when own MarkRead bounces).
              if (m.isMe && !m.isRead && readerId != m.senderId) {
                return m.copyWith(isRead: true);
              }
              return m;
            }).toList();
            state = state.copyWith(messages: updated);
            return;
          }

          if (evt.type == 'chat.message.deleted') {
            final messageId = p['message_id']?.toString() ?? '';
            if (messageId.isEmpty) return;
            state = state.copyWith(
              messages: state.messages
                  .where((m) => m.id != messageId)
                  .toList(),
            );
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

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiEndpoints.chatMessages(chatId));
      final data = response.data['data'];
      if (data is List) {
        final messages = data
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        state = ChatMessagesState(messages: messages);
      } else {
        state = const ChatMessagesState(messages: []);
      }
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] load error: $e');
      state = const ChatMessagesState(messages: []);
    }
  }

  Future<void> sendMessage(
    String text, {
    String? attachedPostId,
    String? attachedMediaUrl,
    String? attachedMediaType,
    int mediaDurationSeconds = 0,
    List<double> waveform = const [],
    ReplyPreview? replyTo,
  }) async {
    final hasMedia = attachedMediaUrl != null && attachedMediaUrl.isNotEmpty;
    // attachedMediaType=='audio' → kind='voice' (бэк-нормализация).
    final kind = attachedPostId != null
        ? 'shared_post'
        : hasMedia
            ? (attachedMediaType == 'audio'
                ? 'voice'
                : (attachedMediaType ?? 'image'))
            : 'text';

    // Optimistic UI: add message locally (no preview yet — server fills it).
    final optimistic = ChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: 'me',
      text: text,
      createdAt: DateTime.now(),
      isMe: true,
      kind: kind,
      attachedMediaUrl: attachedMediaUrl ?? '',
      attachedMediaType: attachedMediaType ?? '',
      mediaDurationSeconds: mediaDurationSeconds,
      waveform: waveform,
      replyTo: replyTo,
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);

    try {
      await _api.post(
        ApiEndpoints.chatMessages(chatId),
        data: {
          'text': text,
          if (attachedPostId != null) 'attached_post_id': attachedPostId,
          if (mediaDurationSeconds > 0)
            'media_duration_seconds': mediaDurationSeconds,
          if (waveform.isNotEmpty) 'waveform': waveform,
          if (replyTo != null) 'reply_to_message_id': replyTo.id,
          if (hasMedia) 'attached_media_url': attachedMediaUrl,
          if (hasMedia)
            'attached_media_type': attachedMediaType ?? 'image',
        },
      );
      // Reload to get the real message with server ID and post preview.
      await load();
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] sendMessage error: $e');
    }
  }

  Future<void> markRead() async {
    try {
      await _api.put(ApiEndpoints.chatRead(chatId));
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] markRead error: $e');
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
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] toggleReaction error: $e');
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

/// Ephemeral "is the peer typing in this chat?" flag. Server-pushed events
/// reset a timer; if no fresh event arrives within [_typingTtl], we clear.
class TypingState {
  final String? userId; // peer who is typing; null when idle
  const TypingState({this.userId});
  bool get isActive => userId != null;
}

class _TypingNotifier extends StateNotifier<TypingState> {
  static const _typingTtl = Duration(seconds: 4);
  final String chatId;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _sub;
  Timer? _expiry;

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
          state = TypingState(userId: uid);
          _expiry?.cancel();
          _expiry = Timer(_typingTtl, () {
            if (mounted) state = const TypingState();
          });
        });
      },
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
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

final chatListProvider = StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ChatListNotifier(api, ref);
});

final chatMessagesProvider =
    StateNotifierProvider.family<ChatMessagesNotifier, ChatMessagesState, String>((ref, chatId) {
  final api = ref.watch(apiClientProvider);
  return ChatMessagesNotifier(chatId, api, ref);
});
