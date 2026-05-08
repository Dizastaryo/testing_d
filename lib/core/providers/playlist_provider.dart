import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/playlist.dart';

/// All playlists owned by the current user.
final myPlaylistsProvider =
    StateNotifierProvider<MyPlaylistsNotifier, AsyncValue<List<Playlist>>>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    return MyPlaylistsNotifier(api);
  },
);

class MyPlaylistsNotifier extends StateNotifier<AsyncValue<List<Playlist>>> {
  final ApiClient _api;
  MyPlaylistsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final r = await _api.get(ApiEndpoints.myPlaylists);
      final data = r.data['data'];
      final list = data is List
          ? data
              .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
              .toList()
          : <Playlist>[];
      state = AsyncValue.data(list);
    } catch (e, st) {
      debugPrint('[MyPlaylistsNotifier] load error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<Playlist?> create(String name) async {
    try {
      final r = await _api.post(ApiEndpoints.createPlaylist,
          data: {'name': name});
      final p = Playlist.fromJson(r.data['data'] as Map<String, dynamic>);
      final current = state.value ?? const <Playlist>[];
      state = AsyncValue.data([p, ...current]);
      return p;
    } catch (e) {
      debugPrint('[MyPlaylistsNotifier] create error: $e');
      return null;
    }
  }

  Future<bool> rename(String id, String name) async {
    try {
      await _api.patch(ApiEndpoints.playlistById(id), data: {'name': name});
      final current = state.value ?? const <Playlist>[];
      state = AsyncValue.data(current
          .map((p) => p.id == id
              ? Playlist(
                  id: p.id,
                  userId: p.userId,
                  name: name,
                  coverUrl: p.coverUrl,
                  tracksCount: p.tracksCount,
                )
              : p)
          .toList());
      return true;
    } catch (e) {
      debugPrint('[MyPlaylistsNotifier] rename error: $e');
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _api.delete(ApiEndpoints.playlistById(id));
      final current = state.value ?? const <Playlist>[];
      state = AsyncValue.data(current.where((p) => p.id != id).toList());
      return true;
    } catch (e) {
      debugPrint('[MyPlaylistsNotifier] delete error: $e');
      return false;
    }
  }

  /// Adds a track and reloads the list (server updates cover_url + tracks_count).
  Future<bool> addTrack(String playlistId, String trackId) async {
    try {
      await _api.post(ApiEndpoints.playlistTracks(playlistId),
          data: {'track_id': trackId});
      await load();
      return true;
    } catch (e) {
      debugPrint('[MyPlaylistsNotifier] addTrack error: $e');
      return false;
    }
  }
}

/// Detail (playlist + tracks) for one playlist. Family-keyed by playlist id.
final playlistDetailProvider = StateNotifierProvider.family<
    PlaylistDetailNotifier, AsyncValue<PlaylistDetail>, String>((ref, id) {
  final api = ref.watch(apiClientProvider);
  return PlaylistDetailNotifier(api, id);
});

class PlaylistDetailNotifier extends StateNotifier<AsyncValue<PlaylistDetail>> {
  final ApiClient _api;
  final String _playlistId;
  PlaylistDetailNotifier(this._api, this._playlistId)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final r = await _api.get(ApiEndpoints.playlistById(_playlistId));
      final detail =
          PlaylistDetail.fromJson(r.data['data'] as Map<String, dynamic>);
      state = AsyncValue.data(detail);
    } catch (e, st) {
      debugPrint('[PlaylistDetailNotifier] load error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> removeTrack(String trackId) async {
    try {
      await _api
          .delete(ApiEndpoints.playlistTrackById(_playlistId, trackId));
      await load();
      return true;
    } catch (e) {
      debugPrint('[PlaylistDetailNotifier] removeTrack error: $e');
      return false;
    }
  }
}
