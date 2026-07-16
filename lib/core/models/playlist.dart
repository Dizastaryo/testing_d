import '../api/api_endpoints.dart';
import 'audio_track.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class Playlist {
  final String id;
  final String userId;
  final String name;
  final String coverUrl;
  final int tracksCount;

  /// До 4 обложек треков — из них собирается мозаика 2×2. Пусто, пока в
  /// плейлисте нет треков с обложками: тогда рисуем сплошной цвет.
  final List<String> coverUrls;

  const Playlist({
    required this.id,
    required this.userId,
    required this.name,
    required this.coverUrl,
    required this.tracksCount,
    this.coverUrls = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        coverUrl: _absUrl(j['cover_url']?.toString()),
        tracksCount: (j['tracks_count'] as num?)?.toInt() ?? 0,
        coverUrls: (j['cover_urls'] as List? ?? [])
            .map((e) => _absUrl(e?.toString()))
            .where((e) => e.isNotEmpty)
            .toList(),
      );
}

class PlaylistDetail {
  final Playlist playlist;
  final List<AudioTrack> tracks;

  const PlaylistDetail({required this.playlist, required this.tracks});

  factory PlaylistDetail.fromJson(Map<String, dynamic> j) {
    final tracksData = j['tracks'];
    final tracks = tracksData is List
        ? tracksData
            .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
            .toList()
        : <AudioTrack>[];
    return PlaylistDetail(
      playlist: Playlist.fromJson(j),
      tracks: tracks,
    );
  }
}
