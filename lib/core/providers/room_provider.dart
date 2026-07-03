import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/room.dart';
import 'auth_provider.dart';
import 'realtime_provider.dart';

// ─── Room list ────────────────────────────────────────────────────

class RoomListState {
  final List<Room> rooms;
  final bool isLoading;
  const RoomListState({this.rooms = const [], this.isLoading = false});
  RoomListState copyWith({List<Room>? rooms, bool? isLoading}) =>
      RoomListState(rooms: rooms ?? this.rooms, isLoading: isLoading ?? this.isLoading);
}

class RoomListNotifier extends StateNotifier<RoomListState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  RoomListNotifier(this._api, this._ref) : super(const RoomListState()) {
    load();
    _listenRealtime();
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final r = await _api.get(ApiEndpoints.rooms);
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final rooms = (data as List<dynamic>)
          .map((e) => Room.fromJson(e as Map<String, dynamic>))
          .toList();
      state = RoomListState(rooms: rooms, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        const refreshEvents = {
          'room.joined',
          'room.left',
          'room.closed',
          'room.invited',    // added to a private room
          'room.removed',    // removed from a private room
          'room.member_added',
          'room.member_removed',
        };
        if (refreshEvents.contains(evt.type)) {
          load(silent: true);
        } else if (evt.type == 'room.message') {
          final payload = evt.payload is Map<String, dynamic>
              ? evt.payload as Map<String, dynamic>
              : null;
          if (payload == null) return;
          final roomId = payload['room_id'] as String?;
          final msgJson = payload['message'] as Map<String, dynamic>?;
          if (roomId == null || msgJson == null) return;
          final text = msgJson['text'] as String? ?? '';
          final senderUsername = msgJson['sender_username'] as String? ?? '';
          final atStr = msgJson['created_at'] as String?;
          final at = atStr != null ? DateTime.tryParse(atStr) : null;
          state = state.copyWith(
            rooms: state.rooms.map((r) {
              if (r.id != roomId) return r;
              return r.copyWith(
                lastMessage: text,
                lastSenderUsername: senderUsername,
                lastMessageAt: at,
              );
            }).toList(),
          );
        }
      });
    });
  }

  void addRoom(Room room) {

    state = state.copyWith(rooms: [room, ...state.rooms]);
  }

  void removeRoom(String roomId) {
    state = state.copyWith(
      rooms: state.rooms.where((r) => r.id != roomId).toList(),
    );
  }
}

final roomListProvider = StateNotifierProvider<RoomListNotifier, RoomListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return RoomListNotifier(api, ref);
});

// ─── Room detail (single room state + participants) ───────────────

class RoomDetailState {
  final Room? room;
  final bool isLoading;
  const RoomDetailState({this.room, this.isLoading = false});
  RoomDetailState copyWith({Room? room, bool? isLoading}) =>
      RoomDetailState(room: room ?? this.room, isLoading: isLoading ?? this.isLoading);
}

class RoomDetailNotifier extends StateNotifier<RoomDetailState> {
  final String roomId;
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;
  Timer? _voiceJoinDebounce; // #H-5

  RoomDetailNotifier(this.roomId, this._api, this._ref) : super(const RoomDetailState()) {
    load();
    _listenRealtime();
  }

  @override
  void dispose() {
    _wsSub?.close();
    _voiceJoinDebounce?.cancel(); // #H-5
    super.dispose();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final r = await _api.get(ApiEndpoints.roomById(roomId));
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      if (mounted) {
        state = RoomDetailState(room: Room.fromJson(data as Map<String, dynamic>));
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        final payload = evt.payload is Map<String, dynamic>
            ? evt.payload as Map<String, dynamic>
            : null;
        if (payload?['room_id'] != roomId) return;

        switch (evt.type) {
          case 'room.joined':
            _handleJoined(payload!);
          case 'room.left':
            _handleLeft(payload!);
          case 'room.muted':
            _handleMuted(payload!);
          case 'room.closed':
            if (state.room != null) {
              state = state.copyWith(room: state.room!.copyWith(isActive: false));
            }
          case 'room.updated':
            if (payload != null && state.room != null) {
              state = state.copyWith(
                room: state.room!.copyWith(
                  name: payload['name'] as String?,
                  description: payload['description'] as String?,
                  coverUrl: payload['cover_url'] as String?,
                ),
              );
            }
          case 'room.voice.joined':
            if (payload != null) _handleVoiceJoined(payload);
          case 'room.voice.left':
            if (payload != null) _handleVoiceLeft(payload);
        }
      });
    });
  }

  void _handleJoined(Map<String, dynamic> p) {
    final room = state.room;
    if (room == null) return;
    // Refresh to get full participant data
    load();
  }

  void _handleLeft(Map<String, dynamic> p) {
    final room = state.room;
    if (room == null) return;
    final userId = p['user_id'] as String?;
    final updated = room.participants.where((pt) => pt.userId != userId).toList();
    state = state.copyWith(
      room: room.copyWith(
        participants: updated,
        participantCount: updated.length,
      ),
    );
  }

  void _handleMuted(Map<String, dynamic> p) {
    final room = state.room;
    if (room == null) return;
    final userId = p['user_id'] as String?;
    final isMuted = p['is_muted'] as bool? ?? false;
    final updated = room.participants.map((pt) {
      if (pt.userId == userId) return pt.copyWith(isMuted: isMuted);
      return pt;
    }).toList();
    // #H-6: если событие касается текущего пользователя (например
    // принудительный мут от модератора) — синхронизируем room.isMuted.
    // Без этого кнопка мута в голосовой панели показывает неверный статус.
    final myId = _ref.read(authProvider).user?.id;
    state = state.copyWith(
      room: room.copyWith(
        participants: updated,
        isMuted: userId == myId ? isMuted : room.isMuted,
      ),
    );
  }

  Future<void> update({
    required String name,
    required String description,
    required String coverUrl,
  }) async {
    final r = await _api.patch(ApiEndpoints.roomById(roomId), data: {
      'name': name,
      'description': description,
      'cover_url': coverUrl,
    });
    final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
    if (mounted) {
      state = RoomDetailState(room: Room.fromJson(data as Map<String, dynamic>));
    }
  }

  /// Optimistically update own mute state, then confirm via server
  void setMyMute(String myUserId, bool muted) {
    final room = state.room;
    if (room == null) return;
    final updated = room.participants.map((pt) {
      if (pt.userId == myUserId) return pt.copyWith(isMuted: muted);
      return pt;
    }).toList();
    state = state.copyWith(
      room: room.copyWith(participants: updated, isMuted: muted),
    );
  }

  void _handleVoiceJoined(Map<String, dynamic> p) {
    // #H-5: дебаунсируем — при одновременном входе N участников не делаем
    // N параллельных HTTP-запросов. Батчим в один load через 300 мс.
    _voiceJoinDebounce?.cancel();
    _voiceJoinDebounce = Timer(const Duration(milliseconds: 300), load);
  }

  void _handleVoiceLeft(Map<String, dynamic> p) {
    final room = state.room;
    if (room == null) return;
    final userId = p['user_id'] as String?;
    final updated = room.voiceParticipants.where((pt) => pt.userId != userId).toList();
    state = state.copyWith(
      room: room.copyWith(
        voiceParticipants: updated,
        voiceCount: updated.length,
      ),
    );
  }

  /// Optimistically mark self as in-voice, call API, roll back on error.
  /// Returns true if the API call succeeded.
  Future<bool> joinVoice(String myUserId) async {
    final room = state.room;
    if (room == null) return false;
    state = state.copyWith(room: room.copyWith(isInVoice: true));
    try {
      await _api.post(ApiEndpoints.roomVoice(roomId));
      return true;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(room: state.room!.copyWith(isInVoice: false));
      }
      return false;
    }
  }

  /// Optimistically mark self as not-in-voice, call API, roll back on error.
  /// Returns true if the API call succeeded.
  Future<bool> leaveVoice(String myUserId) async {
    final room = state.room;
    if (room == null) return false;
    state = state.copyWith(room: room.copyWith(isInVoice: false));
    try {
      await _api.delete(ApiEndpoints.roomVoice(roomId));
      return true;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(room: state.room!.copyWith(isInVoice: true));
      }
      return false;
    }
  }
}

final roomDetailProvider =
    StateNotifierProvider.autoDispose.family<RoomDetailNotifier, RoomDetailState, String>(
  (ref, id) {
    final api = ref.watch(apiClientProvider);
    return RoomDetailNotifier(id, api, ref);
  },
);

// ─── Room messages ────────────────────────────────────────────────

class RoomMessagesState {
  final List<RoomMessage> messages;
  final bool isLoading;
  final bool isSending;
  /// Non-null while a server-side search is active. Null = show all messages.
  final List<RoomMessage>? searchResults;
  final bool isSearching;
  const RoomMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.searchResults,
    this.isSearching = false,
  });
  RoomMessagesState copyWith({
    List<RoomMessage>? messages,
    bool? isLoading,
    bool? isSending,
    List<RoomMessage>? searchResults,
    bool clearSearch = false,
    bool? isSearching,
  }) =>
      RoomMessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
        searchResults: clearSearch ? null : (searchResults ?? this.searchResults),
        isSearching: isSearching ?? this.isSearching,
      );
}

class RoomMessagesNotifier extends StateNotifier<RoomMessagesState> {
  final String roomId;
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  RoomMessagesNotifier(this.roomId, this._api, this._ref) : super(const RoomMessagesState()) {
    load();
    _listenRealtime();
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final r = await _api.get(ApiEndpoints.roomMessages(roomId));
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final msgs = (data as List<dynamic>)
          .map((e) => RoomMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) state = RoomMessagesState(messages: msgs);
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> send(String text, {String? attachedMediaUrl, String? attachedMediaType}) async {
    if (text.trim().isEmpty && attachedMediaUrl == null) return;
    state = state.copyWith(isSending: true);
    try {
      final body = <String, dynamic>{'text': text.trim()};
      if (attachedMediaUrl != null) body['attached_media_url'] = attachedMediaUrl;
      if (attachedMediaType != null) body['attached_media_type'] = attachedMediaType;
      final r = await _api.post(ApiEndpoints.roomMessages(roomId), data: body);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final msg = RoomMessage.fromJson(data as Map<String, dynamic>);
      // Message will also arrive via WS; use API response as optimistic add
      _appendIfAbsent(msg);
    } finally {
      if (mounted) state = state.copyWith(isSending: false);
    }
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        final payload = evt.payload is Map<String, dynamic>
            ? evt.payload as Map<String, dynamic>
            : null;
        if (payload == null || payload['room_id'] != roomId) return;

        if (evt.type == 'room.message') {
          final msgJson = payload['message'] as Map<String, dynamic>?;
          if (msgJson != null) _appendIfAbsent(RoomMessage.fromJson(msgJson));
          return;
        }

        if (evt.type == 'room.reaction') {
          final msgId = payload['message_id']?.toString() ?? '';
          final emoji = payload['emoji']?.toString() ?? '';
          final userId = payload['user_id']?.toString() ?? '';
          final added = payload['added'] as bool? ?? false;
          if (msgId.isEmpty || emoji.isEmpty) return;
          _applyReaction(msgId, userId, emoji, added);
        }
      });
    });
  }

  /// Applies a reaction event received via WS, updating in-place.
  void _applyReaction(String msgId, String userId, String emoji, bool added) {
    final myId = _ref.read(authProvider).user?.id ?? '';
    final updated = state.messages.map((m) {
      if (m.id != msgId) return m;
      final reactions = Map<String, int>.from(m.reactions);
      final prevEmoji = userId == myId ? m.myReaction : null;

      // Remove previous reaction for this user if known.
      if (prevEmoji != null && prevEmoji.isNotEmpty && prevEmoji != emoji) {
        final prev = (reactions[prevEmoji] ?? 1) - 1;
        if (prev <= 0) {
          reactions.remove(prevEmoji);
        } else {
          reactions[prevEmoji] = prev;
        }
      }

      if (added) {
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      } else {
        final next = (reactions[emoji] ?? 1) - 1;
        if (next <= 0) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = next;
        }
      }

      final myReaction = userId == myId
          ? (added ? emoji : '')
          : m.myReaction;
      return m.copyWith(reactions: reactions, myReaction: myReaction);
    }).toList();
    state = state.copyWith(messages: updated);
  }

  /// Sends a reaction to the server. Optimistic update first, rollback on error.
  Future<void> react(String msgId, String emoji) async {
    final myId = _ref.read(authProvider).user?.id ?? '';
    // Find current state to determine if adding or removing.
    final idx = state.messages.indexWhere((m) => m.id == msgId);
    if (idx == -1) return; // message no longer in list — skip silently
    final msg = state.messages[idx];
    final adding = msg.myReaction != emoji;
    // Optimistic update.
    _applyReaction(msgId, myId, emoji, adding);
    try {
      await _api.post(
        ApiEndpoints.roomMessageReact(roomId, msgId),
        data: {'emoji': emoji},
      );
    } catch (_) {
      // Roll back: invert the optimistic change.
      _applyReaction(msgId, myId, emoji, !adding);
    }
  }

  void _appendIfAbsent(RoomMessage msg) {
    if (!mounted) return;
    if (state.messages.any((m) => m.id == msg.id)) return;
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  /// Searches messages on the server by [q]. Call with empty string to clear.
  Future<void> search(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(clearSearch: true, isSearching: false);
      return;
    }
    state = state.copyWith(isSearching: true);
    try {
      final r = await _api.get(
        ApiEndpoints.roomMessages(roomId),
        queryParameters: {'q': trimmed, 'limit': 50},
      );
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final results = (data as List<dynamic>)
          .map((e) => RoomMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) state = state.copyWith(searchResults: results, isSearching: false);
    } catch (_) {
      if (mounted) state = state.copyWith(isSearching: false);
    }
  }

  void clearSearch() {
    state = state.copyWith(clearSearch: true, isSearching: false);
  }
}

final roomMessagesProvider =
    StateNotifierProvider.autoDispose.family<RoomMessagesNotifier, RoomMessagesState, String>(
  (ref, id) {
    final api = ref.watch(apiClientProvider);
    return RoomMessagesNotifier(id, api, ref);
  },
);

// ─── Room members ─────────────────────────────────────────────────

class RoomMembersState {
  final List<RoomMember> members;
  final bool isLoading;
  final String? error;
  const RoomMembersState({
    this.members = const [],
    this.isLoading = false,
    this.error,
  });
  RoomMembersState copyWith({
    List<RoomMember>? members,
    bool? isLoading,
    String? error,
  }) =>
      RoomMembersState(
        members: members ?? this.members,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class RoomMembersNotifier extends StateNotifier<RoomMembersState> {
  final String roomId;
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  RoomMembersNotifier(this.roomId, this._api, this._ref) : super(const RoomMembersState()) {
    load();
    _listenRealtime();
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final r = await _api.get(ApiEndpoints.roomMembers(roomId));
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final members = (data as List<dynamic>)
          .map((e) => RoomMember.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) state = RoomMembersState(members: members);
    } catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> invite(String userId) async {
    await _api.post(ApiEndpoints.roomInvite(roomId), data: {'user_id': userId});
    await load();
  }

  Future<void> remove(String userId) async {
    await _api.delete(ApiEndpoints.roomMember(roomId, userId));
    if (mounted) {
      state = state.copyWith(
        members: state.members.where((m) => m.userId != userId).toList(),
      );
    }
  }

  Future<void> setAdmin(String userId, {required bool grant}) async {
    if (grant) {
      await _api.post(ApiEndpoints.roomAdmin(roomId, userId));
    } else {
      await _api.delete(ApiEndpoints.roomAdmin(roomId, userId));
    }
    await load();
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        final payload = evt.payload is Map<String, dynamic>
            ? evt.payload as Map<String, dynamic>
            : null;
        if (payload?['room_id'] != roomId) return;
        if (evt.type == 'room.member_added' ||
            evt.type == 'room.member_removed' ||
            evt.type == 'room.admin_changed') {
          load();
        }
      });
    });
  }
}

final roomMembersProvider =
    StateNotifierProvider.autoDispose.family<RoomMembersNotifier, RoomMembersState, String>(
  (ref, id) {
    final api = ref.watch(apiClientProvider);
    return RoomMembersNotifier(id, api, ref);
  },
);
