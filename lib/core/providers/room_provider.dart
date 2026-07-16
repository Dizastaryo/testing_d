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

  /// Вход в комнату по коду доступа. Возвращает id комнаты. Бросает
  /// DioException при неверном коде/закрытой комнате — вызывающий покажет
  /// сообщение. Комната сразу добавляется в список (realtime тоже обновит).
  Future<String> joinByCode(String code) async {
    final r = await _api.post(ApiEndpoints.roomJoinByCode, data: {'code': code.trim()});
    final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
    final room = Room.fromJson(data as Map<String, dynamic>);
    if (!state.rooms.any((x) => x.id == room.id)) {
      state = state.copyWith(rooms: [room, ...state.rooms]);
    }
    return room.id;
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
          final payload = evt.payload is Map
              ? (evt.payload as Map).cast<String, dynamic>()
              : null;
          if (payload == null) return;
          final roomId = payload['room_id']?.toString();
          final msgJson = payload['message'] is Map
              ? (payload['message'] as Map).cast<String, dynamic>()
              : null;
          if (roomId == null || msgJson == null) return;
          final text = msgJson['text']?.toString() ?? '';
          final senderUsername = msgJson['sender_username']?.toString() ?? '';
          final senderId = msgJson['sender_id']?.toString() ?? '';
          final at = DateTime.tryParse(msgJson['created_at']?.toString() ?? '');
          final myId = _ref.read(authProvider).user?.id;
          final updated = state.rooms.map((r) {
            if (r.id != roomId) return r;
            return r.copyWith(
              lastMessage: text,
              lastSenderUsername: senderUsername,
              lastMessageAt: at,
              // Бейдж непрочитанного: чужое сообщение инкрементит счётчик
              // (сбрасывает RoomMessagesNotifier.markRead при входе).
              unreadCount:
                  senderId == myId ? r.unreadCount : r.unreadCount + 1,
            );
          }).toList();
          // Комната с новым сообщением всплывает наверх (как чаты) — раньше
          // порядок обновлялся только следующим полным load().
          final idx = updated.indexWhere((r) => r.id == roomId);
          if (idx > 0) {
            final room = updated.removeAt(idx);
            updated.insert(0, room);
          }
          state = state.copyWith(rooms: updated);
        }
      });
    });
  }

  void addRoom(Room room) {
    state = state.copyWith(rooms: [room, ...state.rooms]);
  }

  /// Сброс бейджа непрочитанного (вызывается при входе в комнату).
  void clearUnread(String roomId) {
    state = state.copyWith(
      rooms: state.rooms
          .map((r) => r.id == roomId ? r.copyWith(unreadCount: 0) : r)
          .toList(),
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
                  name: payload['name']?.toString(),
                  description: payload['description']?.toString(),
                  coverUrl: payload['cover_url']?.toString(),
                ),
              );
            }
          case 'room.voice.joined':
            if (payload != null) _handleVoiceJoined(payload);
          case 'room.voice.left':
            if (payload != null) _handleVoiceLeft(payload);
          case 'room.pinned':
            if (payload != null) _handlePinned(payload);
          case 'room.member_added':
          case 'room.member_removed':
            // BUGS_AUDIT #6: the open room screen previously never reacted
            // to membership changes — participant count/list went silently
            // stale while the screen was open. Reload gets the fresh
            // participants + count, same pattern as _handleJoined.
            // ("You were removed" itself is already handled directly in
            // room_screen.dart's own realtime listener via room.removed /
            // room.member_removed(self) — nothing to add here for that part.)
            load();
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
    final userId = p['user_id']?.toString();
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
    final userId = p['user_id']?.toString();
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

  void _handlePinned(Map<String, dynamic> p) {
    // Payload only carries message_id — refetch to get the full preview
    // (sender_username/text/kind), mirroring chat's reload-on-pin approach.
    load();
  }

  /// Sets (messageId != null) or clears (messageId == null) the pinned
  /// message. Requires admin/creator — server enforces, this just calls it.
  Future<void> setPinnedMessage(String? messageId) async {
    await _api.put(ApiEndpoints.roomPin(roomId), data: {'message_id': messageId});
    await load();
  }

  void _handleVoiceLeft(Map<String, dynamic> p) {
    final room = state.room;
    if (room == null) return;
    final userId = p['user_id']?.toString();
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
  /// Пагинация истории: есть ли страницы старше и идёт ли их загрузка.
  /// Раньше комната грузила ТОЛЬКО первую страницу — история старше была
  /// недостижима (в чатах курсорная пагинация была всегда).
  final bool hasMore;
  final bool isLoadingMore;
  /// Non-null while a server-side search is active. Null = show all messages.
  final List<RoomMessage>? searchResults;
  final bool isSearching;
  const RoomMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.searchResults,
    this.isSearching = false,
  });
  RoomMessagesState copyWith({
    List<RoomMessage>? messages,
    bool? isLoading,
    bool? isSending,
    bool? hasMore,
    bool? isLoadingMore,
    List<RoomMessage>? searchResults,
    bool clearSearch = false,
    bool? isSearching,
  }) =>
      RoomMessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
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

  static const _pageSize = 50;
  int _page = 1;

  /// Per-entry толерантный парсинг (как в чатах): одно «битое» сообщение не
  /// должно ронять всю выдачу.
  List<RoomMessage> _parseMessages(dynamic data) {
    final out = <RoomMessage>[];
    if (data is! List) return out;
    for (final e in data) {
      if (e is! Map) continue;
      try {
        out.add(RoomMessage.fromJson(e.cast<String, dynamic>()));
      } catch (_) {
        // пропускаем битую запись
      }
    }
    return out;
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final r = await _api.get(ApiEndpoints.roomMessages(roomId),
          queryParameters: {'page': '1', 'limit': '$_pageSize'});
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final msgs = _parseMessages(data);
      _page = 1;
      if (mounted) {
        state = RoomMessagesState(
          messages: msgs,
          hasMore: msgs.length >= _pageSize,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  /// Подгрузка страницы старее (скролл к верху списка). Бэкенд отдаёт
  /// page/limit, отсортированные oldest-first внутри страницы — старшая
  /// страница приклеивается В НАЧАЛО списка.
  Future<void> loadOlder() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = _page + 1;
      final r = await _api.get(ApiEndpoints.roomMessages(roomId),
          queryParameters: {'page': '$next', 'limit': '$_pageSize'});
      final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
      final older = _parseMessages(data);
      final existing = state.messages.map((m) => m.id).toSet();
      final fresh = older.where((m) => !existing.contains(m.id)).toList();
      _page = next;
      if (mounted) {
        state = state.copyWith(
          messages: [...fresh, ...state.messages],
          isLoadingMore: false,
          hasMore: older.length >= _pageSize,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> send(
    String text, {
    String? attachedMediaUrl,
    String? attachedMediaType,
    String? forwardedFromMessageId,
    String forwardedFromSourceKind = '',
    String? replyToMessageId,
  }) async {
    if (text.trim().isEmpty && attachedMediaUrl == null) return;
    state = state.copyWith(isSending: true);
    try {
      final body = <String, dynamic>{'text': text.trim()};
      if (attachedMediaUrl != null) body['attached_media_url'] = attachedMediaUrl;
      if (attachedMediaType != null) body['attached_media_type'] = attachedMediaType;
      if (forwardedFromMessageId != null) {
        body['forwarded_from_message_id'] = forwardedFromMessageId;
      }
      if (forwardedFromSourceKind.isNotEmpty) {
        body['forwarded_from_source_kind'] = forwardedFromSourceKind;
      }
      if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
        body['reply_to_message_id'] = replyToMessageId;
      }
      final r = await _api.post(ApiEndpoints.roomMessages(roomId), data: body);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final msg = RoomMessage.fromJson(data as Map<String, dynamic>);
      // Message will also arrive via WS; use API response as optimistic add
      _appendIfAbsent(msg);
    } finally {
      if (mounted) state = state.copyWith(isSending: false);
    }
  }

  /// Optimistic local-only removal — экран вызывает API DELETE сам; на
  /// success WS event подтвердит, на error экран вызовет [restoreMessages].
  void removeLocally(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  /// Восстанавливает полный список (rollback для delete).
  void restoreMessages(List<RoomMessage> snapshot) {
    state = state.copyWith(messages: snapshot);
  }

  /// Оптимистично помечает сообщение как «удалённое для всех».
  void markDeletedForAll(String messageId) {
    _mapAll((m) => m.id == messageId
        ? m.copyWith(text: '', kind: 'deleted', isDeletedForAll: true)
        : m);
  }

  /// Применяет трансформацию и к основной ленте, И к активным результатам
  /// поиска — раньше реакции/правки/удаления не отражались, пока открыт поиск.
  void _mapAll(RoomMessage Function(RoomMessage) f) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages.map(f).toList(),
      searchResults: state.searchResults?.map(f).toList(),
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
        ApiEndpoints.roomMessageEdit(roomId, messageId),
        data: {'text': newText},
      );
    } catch (e) {
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

  Future<void> markRead() async {
    // Локальный бейдж списка комнат сбрасываем сразу — сервер догонит.
    _ref.read(roomListProvider.notifier).clearUnread(roomId);
    try {
      await _api.put(ApiEndpoints.roomRead(roomId));
    } catch (_) {
      // Non-fatal — next open will retry.
    }
  }

  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        final payload = evt.payload is Map
            ? (evt.payload as Map).cast<String, dynamic>()
            : null;
        if (payload == null || payload['room_id']?.toString() != roomId) return;

        if (evt.type == 'room.message') {
          final msgJson = payload['message'] is Map
              ? (payload['message'] as Map).cast<String, dynamic>()
              : null;
          if (msgJson == null) return;
          try {
            _appendIfAbsent(RoomMessage.fromJson(msgJson));
          } catch (_) {
            // битый payload не должен ронять WS-listener
          }
          return;
        }

        if (evt.type == 'room.reaction') {
          final msgId = payload['message_id']?.toString() ?? '';
          final emoji = payload['emoji']?.toString() ?? '';
          final userId = payload['user_id']?.toString() ?? '';
          final added = payload['added'] as bool? ?? false;
          if (msgId.isEmpty || emoji.isEmpty) return;
          _applyReaction(msgId, userId, emoji, added);
          return;
        }

        if (evt.type == 'room.message.edited') {
          final msgJson = payload['message'] is Map
              ? (payload['message'] as Map).cast<String, dynamic>()
              : null;
          if (msgJson == null) return;
          try {
            final msg = RoomMessage.fromJson(msgJson);
            _mapAll((m) => m.id == msg.id ? m.copyWith(text: msg.text) : m);
          } catch (_) {}
          return;
        }

        if (evt.type == 'room.message.deleted') {
          final messageId = payload['message_id']?.toString() ?? '';
          if (messageId.isEmpty) return;
          markDeletedForAll(messageId);
          return;
        }

        if (evt.type == 'room.delivered') {
          final messageId = payload['message_id']?.toString() ?? '';
          if (messageId.isEmpty) return;
          final dc = (payload['delivered_count'] as num?)?.toInt() ?? 0;
          final rc = (payload['read_count'] as num?)?.toInt() ?? 0;
          final rec = (payload['recipients_count'] as num?)?.toInt() ?? 0;
          state = state.copyWith(
            messages: state.messages.map((m) {
              if (m.id != messageId) return m;
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

        if (evt.type == 'room.read') {
          final readerId = payload['reader_id']?.toString() ?? '';
          final ids = (payload['message_ids'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              <String>{};
          final countsByMsg = payload['counts_by_msg'] is Map
              ? (payload['counts_by_msg'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          state = state.copyWith(
            messages: state.messages.map((m) {
              if (m.senderId == readerId || !ids.contains(m.id)) return m;
              final cnt = countsByMsg[m.id];
              if (cnt is Map) {
                final c = cnt.cast<String, dynamic>();
                return m.copyWith(
                  isRead: true,
                  deliveredCount:
                      (c['delivered_count'] as num?)?.toInt() ?? m.deliveredCount,
                  readCount: (c['read_count'] as num?)?.toInt() ?? m.readCount,
                  recipientsCount:
                      (c['recipients_count'] as num?)?.toInt() ?? m.recipientsCount,
                );
              }
              return m.copyWith(isRead: true);
            }).toList(),
          );
          return;
        }
      });
    });
  }

  /// Applies a reaction event (optimistic или WS), updating in-place.
  ///
  /// Идемпотентность для СВОИХ событий: сервер шлёт room.reaction всем
  /// участникам, ВКЛЮЧАЯ автора реакции. Раньше эхо применялось поверх
  /// оптимистичного апдейта и счётчик задваивался («❤️ 2» от одного
  /// человека). Теперь эхо, состояние которого уже отражено в myReaction,
  /// пропускается; событие с другого своего устройства — применяется.
  void _applyReaction(String msgId, String userId, String emoji, bool added) {
    final myId = _ref.read(authProvider).user?.id ?? '';
    _mapAll((m) {
      if (m.id != msgId) return m;

      if (userId == myId) {
        final alreadyApplied =
            added ? m.myReaction == emoji : m.myReaction != emoji;
        if (alreadyApplied) return m; // эхо собственного действия
      }

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
    });
  }

  /// Sends a reaction to the server. Optimistic update first, rollback on error.
  Future<void> react(String msgId, String emoji) async {
    final myId = _ref.read(authProvider).user?.id ?? '';
    // Find current state to determine if adding or removing.
    final idx = state.messages.indexWhere((m) => m.id == msgId);
    if (idx == -1) return; // message no longer in list — skip silently
    final original = state.messages[idx];
    final adding = original.myReaction != emoji;
    // Optimistic update.
    _applyReaction(msgId, myId, emoji, adding);
    try {
      await _api.post(
        ApiEndpoints.roomMessageReact(roomId, msgId),
        data: {'emoji': emoji},
      );
    } catch (_) {
      // Точный откат — вернуть исходное сообщение целиком. Инверсия дельты
      // теряла прежнюю реакцию при replace (❤️→🔥 с ошибкой сети «съедал» ❤️).
      _mapAll((m) => m.id == msgId ? original : m);
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
