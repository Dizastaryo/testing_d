import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';

// Chat models (kept inline since they were previously in mock_service)
class Chat {
  final String id;
  final User otherUser;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;

  const Chat({
    required this.id,
    required this.otherUser,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    final otherUserData = json['other_user'];
    if (otherUserData == null || otherUserData is! Map<String, dynamic>) {
      throw FormatException('Chat.fromJson: missing or invalid "other_user" field');
    }
    return Chat(
      id: json['id']?.toString() ?? '',
      otherUser: User.fromJson(otherUserData),
      lastMessage: json['last_message']?.toString() ?? '',
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      unreadCount: (json['unread_count'] ?? 0) as int,
    );
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

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.isMe = false,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
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
    );
  }
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
  ChatListNotifier(this._api) : super(const ChatListState()) {
    load();
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
  ChatMessagesNotifier(this.chatId, this._api) : super(const ChatMessagesState()) {
    load();
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

  Future<void> sendMessage(String text) async {
    // Optimistic UI: add message locally
    final optimistic = ChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: 'me',
      text: text,
      createdAt: DateTime.now(),
      isMe: true,
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);

    try {
      await _api.post(
        ApiEndpoints.chatMessages(chatId),
        data: {'text': text},
      );
      // Reload to get the real message with server ID
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
}

final chatListProvider = StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ChatListNotifier(api);
});

final chatMessagesProvider =
    StateNotifierProvider.family<ChatMessagesNotifier, ChatMessagesState, String>((ref, chatId) {
  final api = ref.watch(apiClientProvider);
  return ChatMessagesNotifier(chatId, api);
});
