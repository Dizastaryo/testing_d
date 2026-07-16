import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/audio_track.dart';

/// Треки, загруженные автором — секция «Аудиотека» во вкладке «Автор» профиля
/// (§05 A2). Только опубликованные (approved + public) — фильтрует бэк
/// (`GET /audio-tracks/by-user/:userId`).
final authorTracksProvider =
    FutureProvider.autoDispose.family<List<AudioTrack>, String>((ref, userId) async {
  if (userId.isEmpty) return const <AudioTrack>[];
  final api = ref.watch(apiClientProvider);
  final r = await api.get('/audio-tracks/by-user/$userId');
  final body = r.data;
  final data = (body is Map && body.containsKey('data')) ? body['data'] : body;
  if (data is List) {
    return data
        .whereType<Map>()
        .map((j) => AudioTrack.fromJson(j.cast<String, dynamic>()))
        .toList();
  }
  return const <AudioTrack>[];
});
