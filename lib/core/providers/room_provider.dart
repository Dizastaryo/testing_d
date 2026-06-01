import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/room.dart';
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

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
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
          load();
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

  RoomDetailNotifier(this.roomId, this._api, this._ref) : super(const RoomDetailState()) {
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
      final r = await _api.get(ApiEndpoints.roomById(roomId));
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      state = RoomDetailState(room: Room.fromJson(data as Map<String, dynamic>));
    } catch (_) {
      state = state.copyWith(isLoading: false);
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
    state = state.copyWith(room: room.copyWith(participants: updated));
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
    state = RoomDetailState(room: Room.fromJson(data as Map<String, dynamic>));
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
    // Refresh to get updated voice_participants list from server
    load();
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
  Future<void> joinVoice(String myUserId) async {
    final room = state.room;
    if (room == null) return;
    state = state.copyWith(room: room.copyWith(isInVoice: true));
    try {
      await _api.post(ApiEndpoints.roomVoice(roomId));
    } catch (_) {
      if (mounted) {
        state = state.copyWith(room: state.room!.copyWith(isInVoice: false));
      }
    }
  }

  /// Optimistically mark self as not-in-voice, call API, roll back on error.
  Future<void> leaveVoice(String myUserId) async {
    final room = state.room;
    if (room == null) return;
    state = state.copyWith(room: room.copyWith(isInVoice: false));
    try {
      await _api.delete(ApiEndpoints.roomVoice(roomId));
    } catch (_) {
      if (mounted) {
        state = state.copyWith(room: state.room!.copyWith(isInVoice: true));
      }
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
  const RoomMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
  });
  RoomMessagesState copyWith({List<RoomMessage>? messages, bool? isLoading, bool? isSending}) =>
      RoomMessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
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
      state = RoomMessagesState(messages: msgs);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    state = state.copyWith(isSending: true);
    try {
      final r = await _api.post(ApiEndpoints.roomMessages(roomId), data: {'text': text.trim()});
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
        if (evt.type != 'room.message') return;
        final payload = evt.payload is Map<String, dynamic>
            ? evt.payload as Map<String, dynamic>
            : null;
        if (payload?['room_id'] != roomId) return;
        final msgJson = payload?['message'] as Map<String, dynamic>?;
        if (msgJson == null) return;
        _appendIfAbsent(RoomMessage.fromJson(msgJson));
      });
    });
  }

  void _appendIfAbsent(RoomMessage msg) {
    if (state.messages.any((m) => m.id == msg.id)) return;
    state = state.copyWith(messages: [...state.messages, msg]);
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
      state = RoomMembersState(members: members);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> invite(String userId) async {
    await _api.post(ApiEndpoints.roomInvite(roomId), data: {'user_id': userId});
    await load();
  }

  Future<void> remove(String userId) async {
    await _api.delete(ApiEndpoints.roomMember(roomId, userId));
    state = state.copyWith(
      members: state.members.where((m) => m.userId != userId).toList(),
    );
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
