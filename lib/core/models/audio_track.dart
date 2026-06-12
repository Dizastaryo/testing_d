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
  /// MUSIC-2: LRC-формат текст. Пустая = lyrics нет. Frontend парсит через
  /// `parseLrc(String)` (см. ниже) и показывает sing-along scroller.
  final String lyricsLrc;
  final int likesCount;
  final bool isLiked;

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
    this.lyricsLrc = '',
    this.likesCount = 0,
    this.isLiked = false,
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
        lyricsLrc: j['lyrics_lrc']?.toString() ?? '',
        likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
        isLiked: j['is_liked'] == true,
      );

  AudioTrack copyWith({bool? isLiked, int? likesCount}) => AudioTrack(
        id: id,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
        usesCount: usesCount,
        genre: genre,
        userId: userId,
        status: status,
        rejectionReason: rejectionReason,
        lyricsLrc: lyricsLrc,
        likesCount: likesCount ?? this.likesCount,
        isLiked: isLiked ?? this.isLiked,
      );

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// MUSIC-2: одна строка LRC-lyrics с timestamp'ом в миллисекундах.
class LyricLine {
  final int timeMs;
  final String text;
  const LyricLine(this.timeMs, this.text);
}

/// Парсит LRC-формат «[mm:ss.xx]Line\n[mm:ss.xx]Next line\n...».
/// Игнорирует metadata lines («[ar:Artist]», «[ti:Title]» etc).
/// Возвращает sorted-by-time список или пустой если parse failed.
List<LyricLine> parseLrc(String lrc) {
  if (lrc.isEmpty) return const [];
  final regex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]([^\[]*)');
  final out = <LyricLine>[];
  for (final m in regex.allMatches(lrc)) {
    final mm = int.tryParse(m.group(1) ?? '0') ?? 0;
    final ss = int.tryParse(m.group(2) ?? '0') ?? 0;
    final centi = int.tryParse(m.group(3) ?? '0') ?? 0;
    final text = (m.group(4) ?? '').trim();
    if (text.isEmpty) continue;
    final timeMs = mm * 60000 + ss * 1000 + centi * 10;
    out.add(LyricLine(timeMs, text));
  }
  out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return out;
}

/// Текущая строка lyrics для player position. Берёт последнюю с timestamp
/// `<= positionMs`. null если до первой строки.
LyricLine? currentLyricAt(List<LyricLine> lines, int positionMs) {
  if (lines.isEmpty) return null;
  LyricLine? cur;
  for (final l in lines) {
    if (l.timeMs <= positionMs) {
      cur = l;
    } else {
      break;
    }
  }
  return cur;
}
