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

  const Playlist({
    required this.id,
    required this.userId,
    required this.name,
    required this.coverUrl,
    required this.tracksCount,
  });

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        coverUrl: _absUrl(j['cover_url']?.toString()),
        tracksCount: (j['tracks_count'] ?? 0) as int,
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
