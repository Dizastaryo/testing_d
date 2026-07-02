import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/live_stream.dart';
import 'realtime_provider.dart';

class LiveStreamsState {
  final List<LiveStream> streams;
  final bool isLoading;
  final String? error;

  const LiveStreamsState({
    this.streams = const [],
    this.isLoading = false,
    this.error,
  });

  LiveStreamsState copyWith({
    List<LiveStream>? streams,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      LiveStreamsState(
        streams: streams ?? this.streams,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class LiveStreamsNotifier extends StateNotifier<LiveStreamsState> {
  final ApiClient _api;

  LiveStreamsNotifier(this._api) : super(const LiveStreamsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final r = await _api.get(ApiEndpoints.streams);
      final list = <LiveStream>[];
      for (final j in (r.data['data'] as List? ?? []).whereType<Map>()) {
        try {
          list.add(LiveStream.fromJson(j.cast<String, dynamic>()));
        } catch (_) {
          // Один битый ряд не должен обнулять всю вкладку Live — пропускаем.
        }
      }
      state = LiveStreamsState(streams: list);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load();

  /// A followed user went live — prepend their stream if not already listed.
  /// The `live_stream.started` WS payload carries enough to build a card
  /// without a refetch. (Only reaches followers — full discovery still via
  /// [load], but this keeps an open list fresh.)
  void onStreamStarted(Map<String, dynamic> payload) {
    final id = payload['stream_id']?.toString() ?? '';
    if (id.isEmpty || state.streams.any((s) => s.id == id)) return;
    final stream = LiveStream.fromJson({
      'id': id,
      'user_id': payload['user_id']?.toString() ?? '',
      'username': payload['username'],
      'full_name': payload['full_name'],
      'avatar_url': payload['avatar_url'],
      'title': payload['title'],
      'status': 'live',
      'viewer_count': payload['viewer_count'],
      'started_at': payload['started_at'],
    });
    state = state.copyWith(streams: [stream, ...state.streams]);
  }

  void onStreamEnded(String streamId) {
    if (streamId.isEmpty) return;
    final next = state.streams.where((s) => s.id != streamId).toList();
    if (next.length != state.streams.length) {
      state = state.copyWith(streams: next);
    }
  }
}

final liveStreamsProvider =
    StateNotifierProvider<LiveStreamsNotifier, LiveStreamsState>((ref) {
  final api = ref.watch(apiClientProvider);
  final notifier = LiveStreamsNotifier(api);

  // Keep the list live: react to start/stop events pushed over the WS.
  ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
    next.whenData((evt) {
      if (evt.type == 'live_stream.started' && evt.payload is Map) {
        notifier.onStreamStarted(
            Map<String, dynamic>.from(evt.payload as Map));
      } else if (evt.type == 'live_stream.ended' && evt.payload is Map) {
        final id =
            (evt.payload as Map)['stream_id']?.toString() ?? '';
        notifier.onStreamEnded(id);
      }
    });
  });

  return notifier;
});
