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
        if (evt.type == 'room.joined' || evt.type == 'room.left' || evt.type == 'room.closed') {
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
        final payload = evt.payload as Map<String, dynamic>?;
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
        final payload = evt.payload as Map<String, dynamic>?;
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
