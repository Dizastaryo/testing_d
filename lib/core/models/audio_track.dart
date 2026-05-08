import '../api/api_endpoints.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String coverUrl;
  final String audioUrl;
  final int durationSeconds;
  final int usesCount;
  final String genre;
  final String userId;
  /// "pending" | "approved" | "rejected" — empty for legacy seed rows.
  final String status;
  final String rejectionReason;

  AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.audioUrl,
    required this.durationSeconds,
    this.usesCount = 0,
    this.genre = '',
    this.userId = '',
    this.status = 'approved',
    this.rejectionReason = '',
  });

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        artist: j['artist'] ?? '',
        coverUrl: _absUrl(j['cover_url']),
        audioUrl: _absUrl(j['audio_url']),
        durationSeconds: j['duration_seconds'] ?? 0,
        usesCount: j['uses_count'] ?? 0,
        genre: j['genre'] ?? '',
        userId: j['user_id']?.toString() ?? '',
        status: j['status']?.toString() ?? 'approved',
        rejectionReason: j['rejection_reason']?.toString() ?? '',
      );

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
